require "spec_helper"

RSpec.describe Textus::Doctor::Check::IntakeRegistration do
  it "reports an error when manifest references an unregistered handler" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "data", "feeds"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes:
          - { name: feeds, kind: machine }
        entries:
          - key: feeds.foo
            kind: produced
            path: data/feeds/foo.md
            lane: feeds
            source:
              from: fetch
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
      FileUtils.mkdir_p(File.join(textus, "data", "feeds"))
      FileUtils.mkdir_p(File.join(textus, "steps", "fetch"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes:
          - { name: knowledge, kind: canon }
        entries: []
      YAML
      File.write(File.join(textus, "steps", "fetch", "orphan_handler.rb"), <<~RUBY)
        class OrphanHandlerFetch < Textus::Step::Fetch
          def call(config:, args:, **)
            { _meta: {}, body: "" }
          end
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
