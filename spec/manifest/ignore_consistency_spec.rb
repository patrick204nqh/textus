require "spec_helper"

RSpec.describe "ignore-pattern consistency across list and doctor (issue #119)" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  let(:store) do
    store_from_manifest(
      root,
      zones: %w[knowledge],
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - key: skills
            path: knowledge/skills
            zone: knowledge
            owner: human:self
            kind: nested
            nested: true
            index_filename: SKILL.md
            ignore:
              - "**/node_modules/**"
      YAML
      files: {
        "zones/knowledge/skills/alpha/SKILL.md" => "# alpha\n",
        "zones/knowledge/skills/alpha/node_modules/dep/SKILL.md" => "# vendored\n",
      },
    )
  end

  it "enumeration excludes the vendored subtree" do
    keys = store.container.manifest.resolver.enumerate.map { |r| r[:key] }
    expect(keys).to include("skills.alpha")
    expect(keys.any? { |k| k.include?("node") }).to be(false)
  end

  it "doctor reports no key.illegal for the same vendored subtree" do
    issues = Textus::Doctor::Check::IllegalKeys.new(store.container).call
    illegal = issues.select { |i| i["code"] == "key.illegal" }
    expect(illegal).to be_empty
  end

  it "the store is green: list is clean AND doctor is clean on the ignored tree" do
    keys = store.container.manifest.resolver.enumerate.map { |r| r[:key] }
    issues = Textus::Doctor::Check::IllegalKeys.new(store.container).call
    expect(keys).to eq(["skills.alpha"])
    expect(issues.select { |i| i["code"] == "key.illegal" }).to be_empty
  end
end
