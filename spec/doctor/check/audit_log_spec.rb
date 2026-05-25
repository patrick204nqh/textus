require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Doctor::Check::AuditLog do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, writable_by: [human] }
      entries: []
    YAML
  end

  it "returns empty array when there is no audit log" do
    store = Textus::Store.new(root)
    expect(described_class.new(store).call).to eq([])
  end

  it "emits audit.parse_error for an invalid-JSON line" do
    File.write(File.join(root, "audit.log"), "{not json\n")
    store = Textus::Store.new(root)
    issues = described_class.new(store).call
    expect(issues).to include(hash_including(
                                "code" => "audit.parse_error",
                                "level" => "warning",
                                "subject" => a_string_matching(/audit\.log:1\z/),
                              ))
  end
end
