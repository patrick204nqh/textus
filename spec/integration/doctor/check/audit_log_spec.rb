require "spec_helper"

RSpec.describe Textus::Doctor::Check::AuditLog do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries: []
    YAML
  end

  it "returns empty array when there is no audit log" do
    store = Textus::Store.new(root)
    expect(described_class.new(store.container).call).to eq([])
  end

  it "emits audit.parse_error for an invalid-JSON line" do
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "{not json\n")
    store = Textus::Store.new(root)
    issues = described_class.new(store.container).call
    expect(issues).to include(hash_including(
                                "code" => "audit.parse_error",
                                "level" => "warning",
                                "subject" => a_string_matching(/audit\.log:1\z/),
                              ))
  end
end
