require "spec_helper"

RSpec.describe "Pulse contract_etag" do
  include_context "textus_store_fixture"

  before do
    %w[data/knowledge schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:expected_etag) { Textus::Etag.for_contract(store.root) }

  it "includes contract_etag in the pulse envelope" do
    result = store.as("human").pulse(since: 0)
    expect(result["contract_etag"]).to eq(expected_etag)
  end

  it "no longer emits the old manifest_etag key" do
    result = store.as("human").pulse(since: 0)
    expect(result).not_to have_key("manifest_etag")
  end
end
