require "spec_helper"

RSpec.describe "legacy runtime artifact migration" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  it "relocates a legacy audit.log under .run/audit on store load" do
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf }
    YAML
    legacy = File.join(root, "audit.log")
    File.write(legacy, %({"seq":1,"verb":"put","key":"working.foo"}\n))
    File.write(File.join(root, "audit.log.1"), %({"seq":0,"verb":"put","key":"x"}\n))
    File.write(File.join(root, "audit.log.1.meta.json"), %({"min_seq":0,"max_seq":0}\n))

    Textus::Store.new(root)

    expect(File.exist?(legacy)).to be(false)
    expect(File.read(audit_log_path(root))).to include("working.foo")
    expect(File.exist?(File.join(audit_dir_path(root), "audit.log.1"))).to be(true)
    expect(File.exist?(File.join(audit_dir_path(root), "audit.log.1.meta.json"))).to be(true)
  end

  it "is idempotent — a second load is a no-op" do
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf }
    YAML
    File.write(File.join(root, "audit.log"), %({"seq":1}\n))

    Textus::Store.new(root)
    first = File.read(audit_log_path(root))
    Textus::Store.new(root)

    expect(File.read(audit_log_path(root))).to eq(first)
  end
end
