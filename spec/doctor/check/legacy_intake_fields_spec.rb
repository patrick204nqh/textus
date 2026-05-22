require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Doctor::Check::LegacyIntakeFields do
  # The check reads the raw YAML, so we construct a Store against a valid
  # manifest first, then overwrite the file with one carrying the legacy
  # fields. This mimics the case the check exists for: a user edited the
  # manifest by hand to a pre-0.9.2 shape and is running doctor on it.
  def with_problem_manifest(legacy_yaml)
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "inbox"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: inbox, writable_by: [script] }
        entries: []
      YAML

      store = Textus::Store.new(textus)
      File.write(File.join(textus, "manifest.yaml"), legacy_yaml)
      yield store
    end
  end

  it "fails when an entry carries intake.ttl" do
    legacy = <<~YAML
      version: textus/2
      zones:
        - { name: inbox, writable_by: [script] }
      entries:
        - key: inbox.notes
          path: inbox/notes.md
          zone: inbox
          intake:
            handler: local_file
            ttl: 10m
    YAML

    with_problem_manifest(legacy) do |store|
      issues = described_class.new(store).call
      bad = issues.find { |i| i["code"] == "manifest.legacy_intake_fields" }
      expect(bad).not_to be_nil
      expect(bad["subject"]).to eq("inbox.notes")
      expect(bad["level"]).to eq("error")
      expect(bad["fix"]).to include("policies: block")
    end
  end

  it "fails when an entry carries intake.on_stale" do
    legacy = <<~YAML
      version: textus/2
      zones:
        - { name: inbox, writable_by: [script] }
      entries:
        - key: inbox.notes
          path: inbox/notes.md
          zone: inbox
          intake:
            handler: local_file
            on_stale: sync
    YAML

    with_problem_manifest(legacy) do |store|
      issues = described_class.new(store).call
      expect(issues.first["message"]).to include("on_stale")
    end
  end

  it "is silent when intake blocks carry only handler/config" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "inbox"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: inbox, writable_by: [script] }
        entries:
          - key: inbox.notes
            path: inbox/notes.md
            zone: inbox
            intake:
              handler: local_file
              config: { path: x.md }
        policies:
          - match: inbox.notes
            refresh: { ttl: 10m }
      YAML

      store = Textus::Store.new(textus)
      expect(described_class.new(store).call).to eq([])
    end
  end
end
