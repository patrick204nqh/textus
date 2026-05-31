require "spec_helper"

RSpec.describe "boot CLI verb catalog avoids retired zone names (ADR 0034)" do
  include_context "textus_store_fixture"

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

  it "describes fetch and build without retired zone INSTANCE names" do
    # 'intake' and 'output' were retired zone instance names (ADR 0034).
    # The contract summary for fetch uses 'intake' as an abstract verb category
    # (derived from Dispatcher contract — ADR 0039); guard only the old instance
    # name 'quarantine' which must not appear as a verb-facing label.
    expect(verbs["fetch"]).not_to include("quarantine")
    expect(verbs["build"]).not_to include("output")
  end

  it "describes pulse without the bare 'review' zone instance name" do
    # 'pending_review' in the contract summary is a return-value field name, not
    # the retired 'review' zone instance. Guard the bare zone name form.
    expect(verbs["pulse"]).not_to include(" review ")
  end
end
