require "spec_helper"

RSpec.describe Textus::Doctor::Check::StaleReviewedStamp do
  include_context "textus_store_fixture"

  def store_with_doc(body)
    store_from_manifest(root, lanes: ["knowledge"], manifest: <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, lane: knowledge, kind: leaf }
    YAML
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "data/knowledge/doc.md"), body)
    Textus::Store.new(root)
  end

  let(:current_minor) { Textus::VERSION.split(".").map(&:to_i)[1] }
  let(:stale_minor)   { current_minor - 6 }
  let(:fresh_minor)   { current_minor - 2 }

  it "warns when stamp is more than 5 minor versions behind" do
    body = "# Doc\n\n> **SSoT for** x · **reviewed** 2025-01 (v0.#{stale_minor})\n\nbody"
    issues = described_class.new(store_with_doc(body).container).call
    expect(issues.size).to eq(1)
    expect(issues.first["code"]).to eq("stale_reviewed_stamp")
    expect(issues.first["subject"]).to eq("knowledge.doc")
    expect(issues.first["level"]).to eq("warning")
  end

  it "passes when stamp is within the 5 minor version threshold" do
    body = "# Doc\n\n> **SSoT for** x · **reviewed** 2026-05 (v0.#{fresh_minor})\n\nbody"
    issues = described_class.new(store_with_doc(body).container).call
    expect(issues).to be_empty
  end

  it "passes when the doc has no reviewed stamp" do
    body = "# Doc\n\nNo stamp header here.\n\nbody"
    issues = described_class.new(store_with_doc(body).container).call
    expect(issues).to be_empty
  end

  it "passes when the stamp version equals the current version" do
    body = "# Doc\n\n> **SSoT for** x · **reviewed** 2026-06 (v#{Textus::VERSION[/\A\d+\.\d+/]})\n\nbody"
    issues = described_class.new(store_with_doc(body).container).call
    expect(issues).to be_empty
  end
end
