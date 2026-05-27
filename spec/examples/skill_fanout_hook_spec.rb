require "spec_helper"
require "fileutils"
require "tmpdir"

require_relative "../../examples/claude-plugin/recipes/skill_fanout"

# Exercises the skill_fanout recipe against a real Textus::Store so the
# spec depends only on the public Application::Context + Operations
# contract that hooks actually receive at runtime.
RSpec.describe "skill_fanout :entry_refreshed listener" do
  include_context "textus_store_fixture"

  let(:store) do
    FileUtils.mkdir_p(File.join(root, "zones/intake/skills"))
    FileUtils.mkdir_p(File.join(root, "zones/vendor/skills"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, write_policy: [human, runner, agent] }
        - { name: vendor, write_policy: [human, runner, agent] }
      entries:
        - { key: intake.skills, path: intake/skills, zone: intake, schema: null, owner: o, nested: true }
        - { key: vendor.skills, path: vendor/skills, zone: vendor, schema: null, owner: o, nested: true }
    YAML

    Textus::Store.new(root)
  end

  let(:ops) { Textus::Operations.for(store, role: "runner") }

  before do
    # The recipe queues its registration via Textus.hook. Drain and apply
    # against the per-store registry so the listener is wired up.
    Textus.drain_hook_blocks # discard any stale leftover from prior load
    TextusRecipes::SkillFanout.register
    Textus.drain_hook_blocks.each { |b| b.call(store.bus) }
  end

  def trigger(key:, files:)
    handler = store.bus.pubsub_handlers(:entry_refreshed).find { |h| h[:name] == :skill_fanout }
    envelope = { "content" => { "files" => files } }
    handler[:callable].call(store: store, key: key, envelope: envelope, change: :updated)
  end

  def derived_keys(slug)
    ops.list(prefix: "vendor.skills.#{slug}").map { |row| row["key"] }
  end

  def derived_envelope(key)
    ops.get(key)
  end

  it "writes one derived entry per file under vendor.skills.<slug>" do
    trigger(
      key: "intake.skills.agent-eval",
      files: {
        "skill.md" => "# skill body",
        "scripts/run.rb" => "puts :ok",
      },
    )

    expect(derived_keys("agent-eval")).to contain_exactly(
      "vendor.skills.agent-eval.skill.md",
      "vendor.skills.agent-eval.scripts.run.rb",
    )
  end

  it "stamps meta with source_key and source_path on each derived entry" do
    trigger(key: "intake.skills.agent-eval", files: { "scripts/run.rb" => "puts :ok" })

    envelope = derived_envelope("vendor.skills.agent-eval.scripts.run.rb")
    expect(envelope.meta["source_key"]).to eq("intake.skills.agent-eval")
    expect(envelope.meta["source_path"]).to eq("scripts/run.rb")
  end

  it "deletes derived keys that no longer appear in the new file set" do
    # Seed orphan + survivors.
    trigger(
      key: "intake.skills.agent-eval",
      files: {
        "skill.md" => "x",
        "scripts/old.rb" => "stale",
        "scripts/run.rb" => "y",
      },
    )
    expect(derived_keys("agent-eval")).to include("vendor.skills.agent-eval.scripts.old.rb")

    # Re-trigger without the orphan.
    trigger(
      key: "intake.skills.agent-eval",
      files: {
        "skill.md" => "x",
        "scripts/run.rb" => "y",
      },
    )

    expect(derived_keys("agent-eval")).to contain_exactly(
      "vendor.skills.agent-eval.skill.md",
      "vendor.skills.agent-eval.scripts.run.rb",
    )
  end

  it "is a no-op for refreshed keys outside the intake.skills.* prefix" do
    trigger(key: "intake.feeds.news", files: { "a" => "b" })
    expect(ops.list(prefix: "vendor")).to be_empty
  end
end
