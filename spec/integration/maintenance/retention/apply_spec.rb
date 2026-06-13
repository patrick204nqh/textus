require "spec_helper"

RSpec.describe Textus::Maintenance::Retention::Apply do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root, zones: %w[knowledge],
            manifest: <<~YAML,
              version: textus/3
              zones:
                - { name: knowledge, kind: canon }
              entries:
                - { key: knowledge.note, path: knowledge/note.md, zone: knowledge, kind: leaf }
            YAML
            files: { "data/knowledge/note.md" => "---\n---\nbody\n" }
    )
  end

  it "drops a row marked drop and reports the dropped key" do
    rows = [{ "key" => "knowledge.note", "action" => "drop",
              "path" => File.join(root, "data/knowledge/note.md") }]

    out = described_class.new(container: store.container, call: test_ctx(role: "human")).call(rows)

    expect(out[:dropped]).to eq(["knowledge.note"])
    expect(File.exist?(File.join(root, "data/knowledge/note.md"))).to be(false)
  end

  it "archives a row marked archive, copying under archive/ before deletion" do
    rows = [{ "key" => "knowledge.note", "action" => "archive",
              "path" => File.join(root, "data/knowledge/note.md") }]

    out = described_class.new(container: store.container, call: test_ctx(role: "human")).call(rows)

    expect(out[:archived]).to eq(["knowledge.note"])
    expect(File.exist?(File.join(root, "archive/data/knowledge/note.md"))).to be(true)
  end
end
