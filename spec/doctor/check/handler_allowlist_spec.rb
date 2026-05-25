require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Doctor::Check::HandlerAllowlist do
  def with_store(manifest_yaml)
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "intake"))
      File.write(File.join(textus, "manifest.yaml"), manifest_yaml)
      yield Textus::Store.new(textus)
    end
  end

  it "is silent when the declared handler is in the allowlist" do
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: intake, writable_by: [script] }
      entries:
        - key: intake.notes
          path: intake/notes.md
          zone: intake
          intake:
            handler: local_file
      policies:
        - match: intake.*
          handler_allowlist: [local_file, json]
    YAML

    with_store(manifest) do |store|
      issues = described_class.new(store).call
      expect(issues).to eq([])
    end
  end

  it "fails when the declared handler is not in the allowlist" do
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: intake, writable_by: [script] }
      entries:
        - key: intake.notes
          path: intake/notes.md
          zone: intake
          intake:
            handler: shady_handler
      policies:
        - match: intake.*
          handler_allowlist: [local_file, json]
    YAML

    with_store(manifest) do |store|
      issues = described_class.new(store).call
      bad = issues.find { |i| i["code"] == "policy.handler_not_allowed" }
      expect(bad).not_to be_nil
      expect(bad["subject"]).to eq("intake.notes")
      expect(bad["level"]).to eq("error")
      expect(bad["message"]).to include("shady_handler")
      expect(bad["message"]).to include("local_file")
    end
  end

  it "is silent when no allowlist policy applies" do
    manifest = <<~YAML
      version: textus/3
      zones:
        - { name: intake, writable_by: [script] }
      entries:
        - key: intake.notes
          path: intake/notes.md
          zone: intake
          intake:
            handler: anything_goes
    YAML

    with_store(manifest) do |store|
      expect(described_class.new(store).call).to eq([])
    end
  end
end
