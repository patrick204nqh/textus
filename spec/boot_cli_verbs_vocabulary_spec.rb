require "spec_helper"

RSpec.describe "boot CLI verb catalog avoids retired zone names (ADR 0034)" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      roles: [{ name: human, can: [author] }]
      zones: [{ name: knowledge, kind: canon }]
      entries: []
    YAML
  end

  let(:verbs) do
    Textus::Boot.build(container: store.container)["cli_verbs"].to_h { |v| [v["name"], v["summary"]] }
  end

  it "describes accept as a queued-proposal promotion, not 'review.*'" do
    expect(verbs["accept"]).not_to include("review")
    expect(verbs["accept"]).to include("proposal")
  end

  it "describes fetch and build without retired zone names" do
    expect(verbs["fetch"]).not_to include("intake")
    expect(verbs["build"]).not_to include("output")
  end

  it "describes pulse without the bare 'review' instance name" do
    expect(verbs["pulse"]).not_to include("review")
  end
end
