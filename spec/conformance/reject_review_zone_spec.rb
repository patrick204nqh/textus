require "spec_helper"

# Regression test for proposal-zone detection: store.reject must accept a
# proposal in any zone that declares `kind: queue` (regardless of its name),
# and refuse in a non-queue zone. Detection keys off the declared zone kind
# (`in_proposal_zone?` => `declared_kind == :queue`), not the zone name or its
# writers. (Historically this was a hardcoded `zone == "pending"` check, then a
# writer-signal heuristic; 0.30.0 made the declared kind authoritative.)
RSpec.describe "store.reject with declared-kind proposal-zone detection" do
  include_context "textus_store_fixture"

  it "accepts a proposal in a zone declaring kind: queue (named 'proposals')" do
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/proposals"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: proposals,   kind: queue }
      entries:
        - { key: identity.target, path: identity/target.md, zone: identity, kind: leaf}

        - { key: proposals.draft,    path: proposals/draft.md,    zone: proposals, kind: leaf}

    YAML

    store = Textus::Store.new(root)
    store.as("agent").put(
      "proposals.draft",
      meta: { "name" => "draft", "proposal" => { "target_key" => "identity.target", "action" => "put" } },
      body: "proposed body",
    )

    result = store.as("human").reject("proposals.draft")
    expect(result["rejected"]).to eq("proposals.draft")
    expect(result["target_key"]).to eq("identity.target")
    expect(store.as(Textus::Role::DEFAULT).get("proposals.draft")).to be_nil
  end

  it "refuses: a zone declaring kind: canon is not a proposal zone (even if named 'pending')" do
    # Declared-kind check: the zone is not kind: queue, so it is not a proposal
    # zone and reject must refuse — regardless of the zone's name.
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/pending"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: pending,  kind: canon }
      entries:
        - { key: identity.target, path: identity/target.md, zone: identity, kind: leaf}

        - { key: pending.draft,   path: pending/draft.md,   zone: pending, kind: leaf}

    YAML

    store = Textus::Store.new(root)
    store.as("human").put(
      "pending.draft",
      meta: { "name" => "draft", "proposal" => { "target_key" => "identity.target", "action" => "put" } },
      body: "x",
    )
    expect { store.as("human").reject("pending.draft") }
      .to raise_error(Textus::ProposalError, /not in a proposal zone/)
  end
end
