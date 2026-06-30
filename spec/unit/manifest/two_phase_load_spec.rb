require "spec_helper"

RSpec.describe "Manifest two-phase initialization" do
  def build_manifest_with_produced_entry(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: canon,     kind: canon    }
        - { name: artifacts, kind: machine  }
      entries:
        - key: artifacts.derived
          path: artifacts/derived.md
          lane: artifacts
          owner: automation:self
          kind: produced
    YAML
    Textus::Manifest.load(root)
  end

  it "derived_entry? returns true for a produced entry after load" do
    Dir.mktmpdir do |tmp|
      root = File.join(tmp, ".textus")
      FileUtils.mkdir_p(root)
      manifest = build_manifest_with_produced_entry(root)
      expect(manifest.policy.derived_entry?("artifacts.derived")).to be(true)
    end
  end

  it "derived_entry? returns false for a non-existent or non-produced entry" do
    Dir.mktmpdir do |tmp|
      root = File.join(tmp, ".textus")
      FileUtils.mkdir_p(root)
      manifest = build_manifest_with_produced_entry(root)
      expect(manifest.policy.derived_entry?("nonexistent")).to be(false)
    end
  end
end
