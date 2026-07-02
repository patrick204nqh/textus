require "spec_helper"

RSpec.describe "naming-check workflow" do
  include_context "textus_store_fixture"

  def build_store
    FileUtils.mkdir_p(File.join(root, "data/knowledge/judgment"))
    store_from_manifest(root, lanes: %w[knowledge artifacts], files: {
                          "workflows/config/naming_check.rb" => File.read(".textus/workflows/config/naming_check.rb"),
                        }, manifest: <<~YAML)
                          version: textus/4
                          data:
                            knowledge:
                              - key: knowledge.judgment
                                naming: sequential
                            artifacts:
                              - key: artifacts.doctor.naming-check
                                format: json
                        YAML
  end

  it "flags a file that doesn't match its entry's declared naming" do
    store = build_store
    File.write(File.join(root, "data/knowledge/judgment/not-numbered.md"), "content")

    converge_now(store)

    result = store.get(key: "artifacts.doctor.naming-check")
    issues = result.content["issues"]
    expect(issues).not_to be_empty
    expect(issues.first).to include("code", "level", "subject", "message", "fix")
  end

  it "reports no issues for a correctly-named file" do
    store = build_store
    File.write(File.join(root, "data/knowledge/judgment/0001-topic.md"), "content")

    converge_now(store)

    result = store.get(key: "artifacts.doctor.naming-check")
    issues = result.content["issues"]
    expect(issues).to be_empty
  end
end
