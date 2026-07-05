require "spec_helper"

RSpec.describe "naming-convention check" do
  include_context "textus_store_fixture"

  def build_store
    FileUtils.mkdir_p(File.join(root, "data/knowledge/loop/judgment"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts"))
    File.write(File.join(root, "data/artifacts/doctor.json"), JSON.dump({}))
    store_from_manifest(root, lanes: %w[knowledge artifacts], files: {
                          "workflows/config/doctors.rb" => File.read(".textus/workflows/config/doctors.rb"),
                        }, manifest: <<~YAML)
                          version: textus/4
                          data:
                            knowledge:
                              - key: knowledge.loop.judgment
                                naming: sequential
                            artifacts:
                              - key: artifacts.doctor
                                format: json
                        YAML
  end

  it "flags a file that doesn't match its entry's declared naming" do
    store = build_store
    File.write(File.join(root, "data/knowledge/loop/judgment/not-numbered.md"), "content")

    converge_now(store)

    result = store.get(key: "artifacts.doctor")
    issues = result["content"]["issues"]
    expect(issues).not_to be_empty
    expect(issues.first).to include("code", "level", "subject", "message", "fix")
  end

  it "reports no issues for a correctly-named file" do
    store = build_store
    File.write(File.join(root, "data/knowledge/loop/judgment/0001-topic.md"), "content")

    converge_now(store)

    result = store.get(key: "artifacts.doctor")
    issues = result["content"]["issues"]
    expect(issues).to be_empty
  end
end
