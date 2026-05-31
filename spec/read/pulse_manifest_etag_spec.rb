require "spec_helper"

RSpec.describe "Pulse manifest_etag" do
  include_context "textus_store_fixture"

  before do
    %w[zones/working schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:expected_etag) { Textus::Etag.for_file(File.join(root, "manifest.yaml")) }

  it "includes manifest_etag in the pulse envelope" do
    result = store.as("human").pulse(since: 0)
    expect(result["manifest_etag"]).to eq(expected_etag)
  end
end
