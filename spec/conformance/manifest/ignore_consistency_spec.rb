require "spec_helper"

RSpec.describe "ignore-pattern consistency across list and doctor (issue #119)" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  let(:illegal_keys_workflow) do
    File.read(File.expand_path("../../../.textus/workflows/config/doctor_illegal_keys.rb", __dir__))
  end

  let(:store) do
    store_from_manifest(
      root,
      lanes: %w[knowledge artifacts],
      manifest: <<~YAML,
        version: textus/4
        lanes:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: machine }
        entries:
          - key: skills
            path: knowledge/skills
            lane: knowledge
            owner: human:self
            kind: nested
            ignore:
              - "**/node_modules/**"
          - { key: artifacts.doctor.illegal-keys, lane: artifacts, format: json, kind: produced }
      YAML
      files: {
        "data/knowledge/skills/alpha/intro.md" => "# alpha\n",
        "data/knowledge/skills/alpha/node_modules/dep/intro.md" => "# vendored\n",
        "workflows/config/doctor_illegal_keys.rb" => illegal_keys_workflow,
      },
    )
  end

  it "enumeration excludes the vendored subtree" do
    keys = store.container.manifest.resolver.enumerate.map { |r| r[:key] }
    expect(keys).to include("skills.alpha.intro")
    expect(keys.any? { |k| k.include?("node") }).to be(false)
  end

  it "doctor reports no key.illegal for the same vendored subtree" do
    Textus::Produce::Engine.converge(
      container: store.container,
      call: Textus::Value::Call.build(role: "automation"),
      keys: ["artifacts.doctor.illegal-keys"],
    )
    env = store.with_role("human").get(key: "artifacts.doctor.illegal-keys")
    illegal = env.content.fetch("issues").select { |i| i["code"] == "key.illegal" }
    expect(illegal).to be_empty
  end

  it "the store is green: list is clean AND doctor is clean on the ignored tree" do
    keys = store.container.manifest.resolver.enumerate.map { |r| r[:key] }
    Textus::Produce::Engine.converge(
      container: store.container,
      call: Textus::Value::Call.build(role: "automation"),
      keys: ["artifacts.doctor.illegal-keys"],
    )
    env = store.with_role("human").get(key: "artifacts.doctor.illegal-keys")
    expect(keys).to eq(["skills.alpha.intro"])
    expect(env.content.fetch("issues").select { |i| i["code"] == "key.illegal" }).to be_empty
  end
end
