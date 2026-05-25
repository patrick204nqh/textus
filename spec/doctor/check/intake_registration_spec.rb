require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Doctor::Check::IntakeRegistration do
  it "reports an error when manifest references an unregistered handler" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, writable_by: [human, script] }
        entries:
          - key: working.foo
            path: working/foo.md
            zone: working
            intake:
              handler: nonexistent_handler
      YAML

      store = Textus::Store.new(textus)
      issues = described_class.new(store).call

      offending = issues.find { |i| i["code"] == "intake.handler_missing" }
      expect(offending).not_to be_nil
      expect(offending["subject"]).to eq("nonexistent_handler")
    end
  end

  it "reports a warning for orphan handlers (registered, not in manifest)" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      FileUtils.mkdir_p(File.join(textus, "hooks"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, writable_by: [human, script] }
        entries: []
      YAML
      File.write(File.join(textus, "hooks", "orphan.rb"), <<~RUBY)
        Textus.intake(:orphan_handler) { |store:, config:, args:| { _meta: {}, body: "" } }
      RUBY

      store = Textus::Store.new(textus)
      issues = described_class.new(store).call

      orphan = issues.find { |i| i["code"] == "intake.handler_orphan" }
      expect(orphan).not_to be_nil
      expect(orphan["subject"]).to eq("orphan_handler")
      expect(orphan["level"]).to eq("warning")
    end
  end
end
