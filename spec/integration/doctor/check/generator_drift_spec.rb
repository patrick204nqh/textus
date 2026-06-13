require "spec_helper"

RSpec.describe Textus::Doctor::Check::GeneratorDrift do
  include_context "textus_store_fixture"

  def write_fixture!(generated_at:)
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts,  kind: machine }
      entries:
        - key: knowledge.src
          kind: leaf
          path: knowledge/src.md
          zone: knowledge
        - key: artifacts.catalog
          kind: produced
          path: artifacts/catalog.md
          zone: artifacts
          source:
            from: command
            command: "rake catalog"
            sources: [knowledge.src]
    YAML
    File.write(File.join(root, "data/knowledge/src.md"), "---\nname: src\n---\nbody\n")
    File.write(File.join(root, "data/artifacts/catalog.md"), <<~MD)
      ---
      generated:
        by: "rake catalog"
        at: "#{generated_at}"
        from:
          - knowledge.src
      ---
      catalog
    MD
    File.utime(Time.now, Time.now, File.join(root, "data/knowledge/src.md"))
  end

  def issues
    described_class.new(Textus::Store.new(root).container).call
  end

  it "flags a derived entry whose source changed after generated.at" do
    write_fixture!(generated_at: "2020-01-01T00:00:00Z")
    issue = issues.find { |i| i["code"] == "generator_drift" && i["subject"] == "artifacts.catalog" }
    expect(issue).not_to be_nil
    expect(issue["level"]).to eq("warning")
    expect(issue["message"]).to match(/knowledge\.src/)
  end

  it "is silent when the derived entry is newer than its source" do
    write_fixture!(generated_at: (Time.now + 3600).utc.iso8601)
    expect(issues.map { |i| i["code"] }).not_to include("generator_drift")
  end
end
