require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Write::Reject do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      files: {
        "zones/target.md" => "---\nname: target\n---\nbody\n",
        "zones/draft.md" => "---\nname: draft\nproposal:\n  target_key: identity.target\n---\nbody\n",
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: identity, kind: origin }
          - { name: review, kind: queue }
        entries:
          - { key: identity.target, path: target.md, zone: identity, schema: null, owner: o, kind: leaf }
          - { key: review.draft, path: draft.md, zone: review, schema: null, owner: o, kind: leaf }
      YAML
    )
  end

  it "deletes the proposal and fires :proposal_rejected" do
    events = []
    store.events.register(:proposal_rejected, :capture_reject) { |key:, target_key:, **| events << [key, target_key] }

    res = build_reject(store, test_ctx(role: "human")).call("review.draft")

    expect(res).to include("protocol" => Textus::PROTOCOL, "rejected" => "review.draft", "target_key" => "identity.target")
    expect(events).to eq([["review.draft", "identity.target"]])
    expect(store.as(Textus::Role::DEFAULT).get("review.draft")).to be_nil
  end

  it "rejects non-authority callers with guard_failed naming the predicate" do
    expect { build_reject(store, test_ctx(role: "agent")).call("review.draft") }
      .to fail_guard_with("accept_signed")
  end

  it "rejects entries that are not in a proposal zone" do
    expect { build_reject(store, test_ctx(role: "human")).call("identity.target") }
      .to raise_error(Textus::ProposalError, /not in a proposal zone/)
  end
end
