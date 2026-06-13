require "spec_helper"

RSpec.describe Textus::Doctor::Check::HandlerPermit do
  def with_store(manifest_yaml)
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "data", "intake"))
      File.write(File.join(textus, "manifest.yaml"), manifest_yaml)
      yield Textus::Store.new(textus)
    end
  end

  it "is silent when the declared handler is in the allowlist" do
    manifest = <<~YAML
      version: textus/3
      lanes:
        - { name: intake, kind: machine }
      entries:
        - key: intake.notes
          kind: produced
          path: intake/notes.md
          lane: intake
          source:
            from: fetch
            handler: local_file
      rules:
        - match: intake.*
          handler_permit: [local_file, json]
    YAML

    with_store(manifest) do |store|
      issues = described_class.new(store.container).call
      expect(issues).to eq([])
    end
  end

  it "fails when the declared handler is not in the allowlist" do
    manifest = <<~YAML
      version: textus/3
      lanes:
        - { name: intake, kind: machine }
      entries:
        - key: intake.notes
          kind: produced
          path: intake/notes.md
          lane: intake
          source:
            from: fetch
            handler: shady_handler
      rules:
        - match: intake.*
          handler_permit: [local_file, json]
    YAML

    with_store(manifest) do |store|
      issues = described_class.new(store.container).call
      bad = issues.find { |i| i["code"] == "policy.handler_not_permitted" }
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
      lanes:
        - { name: intake, kind: machine }
      entries:
        - key: intake.notes
          kind: produced
          path: intake/notes.md
          lane: intake
          source:
            from: fetch
            handler: anything_goes
    YAML

    with_store(manifest) do |store|
      expect(described_class.new(store.container).call).to eq([])
    end
  end
end
