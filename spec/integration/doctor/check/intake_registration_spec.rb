require "spec_helper"

RSpec.describe Textus::Doctor::Check::IntakeRegistration do
  it "reports an error when manifest references an unregistered handler" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "feeds"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: feeds, kind: machine }
        entries:
          - key: feeds.foo
            kind: intake
            path: feeds/foo.md
            zone: feeds
            intake:
              handler: nonexistent_handler
      YAML

      store = Textus::Store.new(textus)
      issues = described_class.new(store.container).call

      offending = issues.find { |i| i["code"] == "intake.handler_missing" }
      expect(offending).not_to be_nil
      expect(offending["subject"]).to eq("nonexistent_handler")
    end
  end

  it "reports a warning for orphan handlers (registered, not in manifest)" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "feeds"))
      FileUtils.mkdir_p(File.join(textus, "hooks"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries: []
      YAML
      File.write(File.join(textus, "hooks", "orphan.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :orphan_handler) { |caps:, config:, args:| { _meta: {}, body: "" } }
        end
      RUBY

      store = Textus::Store.new(textus)
      issues = described_class.new(store.container).call

      orphan = issues.find { |i| i["code"] == "intake.handler_orphan" }
      expect(orphan).not_to be_nil
      expect(orphan["subject"]).to eq("orphan_handler")
      expect(orphan["level"]).to eq("warning")
    end
  end
end
