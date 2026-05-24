require "spec_helper"

require_relative "../../examples/claude-plugin/recipes/skill_fanout"

class FakeStore
  attr_reader :puts, :deletes

  def initialize(existing_keys: [])
    @existing = existing_keys
    @puts = []
    @deletes = []
  end

  def list(prefix:, zone: nil)
    _ = zone
    @existing.select { |k| k.start_with?(prefix) }
  end

  def put(key, meta:, body:, suppress_events: false, **_)
    @puts << { key: key, meta: meta, body: body, suppress_events: suppress_events }
  end

  def delete(key, suppress_events: false, **_)
    @deletes << { key: key, suppress_events: suppress_events }
  end
end

RSpec.describe "skill_fanout :refreshed listener" do
  let(:registry) { Textus::Hooks::Registry.new }
  let(:fake_store) { FakeStore.new }

  before do
    Textus.with_registry(registry) { TextusRecipes::SkillFanout.register }
  end

  def trigger(key:, files:, store: fake_store)
    handler = registry.pubsub_handlers(:refreshed).find { |h| h[:name] == :skill_fanout }
    envelope = { "content" => { "files" => files } }
    handler[:callable].call(store: store, key: key, envelope: envelope, change: :updated)
  end

  it "writes one derived entry per file under vendor.skills.<slug>" do
    trigger(
      key: "intake.skills.agent-eval",
      files: {
        "SKILL.md" => "# skill body",
        "scripts/run.rb" => "puts :ok",
      },
    )

    keys = fake_store.puts.map { _1[:key] }
    expect(keys).to contain_exactly(
      "vendor.skills.agent-eval.SKILL.md",
      "vendor.skills.agent-eval.scripts.run.rb",
    )
  end

  it "passes suppress_events: true on every derived put" do
    trigger(key: "intake.skills.agent-eval", files: { "SKILL.md" => "x" })
    expect(fake_store.puts.first[:suppress_events]).to be(true)
  end

  it "stamps meta with source_key and source_path on each derived entry" do
    trigger(key: "intake.skills.agent-eval", files: { "scripts/run.rb" => "puts :ok" })
    meta = fake_store.puts.first[:meta]
    expect(meta["source_key"]).to eq("intake.skills.agent-eval")
    expect(meta["source_path"]).to eq("scripts/run.rb")
  end

  it "deletes derived keys that no longer appear in the new file set" do
    fake_store = FakeStore.new(existing_keys: [
                                 "vendor.skills.agent-eval.SKILL.md",
                                 "vendor.skills.agent-eval.scripts.old.rb",
                                 "vendor.skills.agent-eval.scripts.run.rb",
                               ])
    trigger(
      store: fake_store,
      key: "intake.skills.agent-eval",
      files: {
        "SKILL.md" => "x",
        "scripts/run.rb" => "y",
      },
    )

    deleted = fake_store.deletes.map { _1[:key] }
    expect(deleted).to contain_exactly("vendor.skills.agent-eval.scripts.old.rb")
    expect(fake_store.deletes.first[:suppress_events]).to be(true)
  end

  it "is a no-op for refreshed keys outside the intake.skills.* prefix" do
    trigger(key: "intake.feeds.news", files: { "a" => "b" })
    expect(fake_store.puts).to be_empty
    expect(fake_store.deletes).to be_empty
  end
end
