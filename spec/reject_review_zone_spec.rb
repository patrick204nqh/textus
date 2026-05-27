require "spec_helper"
require "fileutils"
require "tmpdir"

# Regression test for the 0.9.2 zone-rename: a zone named `review` (or any
# non-"pending" name) whose writable_by signals proposal-kind ([ai, human])
# must be acceptable to store.reject. Prior to signal-based detection this
# raised ProposalError because Writer#reject hardcoded `zone == "pending"`.
RSpec.describe "store.reject with signal-based proposal-zone detection" do
  include_context "textus_store_fixture"

  it "accepts a proposal in a zone literally named 'review' (post-0.9.2 default)" do
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/review"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, write_policy: [human] }
        - { name: review,   write_policy: [agent, human] }
      entries:
        - { key: identity.target, path: identity/target.md, zone: identity, kind: leaf}

        - { key: review.draft,    path: review/draft.md,    zone: review, kind: leaf}

    YAML

    store = Textus::Store.new(root)
    Textus::Operations.for(store, role: "agent").put(
      "review.draft",
      meta: { "name" => "draft", "proposal" => { "target_key" => "identity.target", "action" => "put" } },
      body: "proposed body",
    )

    result = Textus::Operations.for(store, role: "human").reject("review.draft")
    expect(result["rejected"]).to eq("review.draft")
    expect(result["target_key"]).to eq("identity.target")
    expect(Textus::Operations.for(store).get("review.draft")).to be_nil
  end

  it "negative-signal: a zone literally named 'pending' but without [ai] writers is NOT proposal-kind" do
    # Pure signal check: even though the zone is *named* pending, without an
    # `ai` writer it is not proposal-kind and reject must refuse.
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/pending"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, write_policy: [human] }
        - { name: pending,  write_policy: [human] }
      entries:
        - { key: identity.target, path: identity/target.md, zone: identity, kind: leaf}

        - { key: pending.draft,   path: pending/draft.md,   zone: pending, kind: leaf}

    YAML

    store = Textus::Store.new(root)
    Textus::Operations.for(store, role: "human").put(
      "pending.draft",
      meta: { "name" => "draft", "proposal" => { "target_key" => "identity.target", "action" => "put" } },
      body: "x",
    )
    expect { Textus::Operations.for(store, role: "human").reject("pending.draft") }
      .to raise_error(Textus::ProposalError, /not in a proposal zone/)
  end
end
