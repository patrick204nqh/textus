require "spec_helper"

RSpec.describe Textus::Action::KeyMv do
  include_context "textus_store_fixture"

  let(:store) do
    FileUtils.mkdir_p(File.join(root, "data/knowledge/notes"))
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, lane: knowledge, kind: nested }
    YAML
  end

  before { store.as("human").put("knowledge.notes.alpha", meta: { "name" => "alpha" }, body: "hello") }

  it "moves an entry and returns the renamed keys" do
    result = store.as("human").key_mv("knowledge.notes.alpha", "knowledge.notes.beta")

    expect(result["ok"]).to be(true)
    expect(result["from_key"]).to eq("knowledge.notes.alpha")
    expect(result["to_key"]).to eq("knowledge.notes.beta")
  end

  it "supports dry_run without writing to disk" do
    result = store.as("human").key_mv("knowledge.notes.alpha", "knowledge.notes.beta", dry_run: true)

    expect(result["dry_run"]).to be(true)
    expect(File.exist?(File.join(root, "data/knowledge/notes/alpha.md"))).to be(true)
    expect(File.exist?(File.join(root, "data/knowledge/notes/beta.md"))).to be(false)
  end

  it "propagates correlation_id from ctx into the audit row" do
    store.as("human", correlation_id: "cid-test").key_mv("knowledge.notes.alpha", "knowledge.notes.beta")

    log_path = Textus::Store::Geometry.new(root).audit_log_path
    rows = File.readlines(log_path, chomp: true).map { |l| JSON.parse(l) }
    mv_row = rows.find { |r| r["verb"] == "key_mv" }
    expect(mv_row.dig("extras", "correlation_id")).to eq("cid-test")
  end
end
