require "spec_helper"
require "tmpdir"
require "fileutils"
require "digest"

RSpec.describe "Pulse manifest_etag" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/working schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:expected_etag) { Digest::SHA256.hexdigest(File.read(File.join(root, "manifest.yaml"))) }

  it "includes manifest_etag in the pulse envelope" do
    result = Textus::Operations.for(store, role: "human").pulse(since: 0)
    expect(result["manifest_etag"]).to eq(expected_etag)
  end
end
