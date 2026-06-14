require "spec_helper"

RSpec.describe Textus::Action::Reject do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(
      root,
      files: {
        "data/target.md" => "---\nname: target\n---\nbody\n",
        "data/draft.md" => "---\nname: draft\nproposal:\n  target_key: identity.target\n---\nbody\n",
      },
      manifest: <<~YAML,
        version: textus/3
        lanes:
          - { name: identity, kind: canon }
          - { name: proposals, kind: queue }
        entries:
          - { key: identity.target, path: target.md, lane: identity, owner: human:self, kind: leaf }
          - { key: proposals.draft, path: draft.md, lane: proposals, owner: human:self, kind: leaf }
      YAML
    )
  end

  it "deletes the proposal and fires :proposal_rejected" do
    events = []
    store.steps.on(:proposal_rejected, :capture_reject) { |key:, target_key:, **| events << [key, target_key] }

    res = store.as("human").reject("proposals.draft")

    expect(res).to include("protocol" => Textus::PROTOCOL, "rejected" => "proposals.draft", "target_key" => "identity.target")
    expect(events).to eq([["proposals.draft", "identity.target"]])
    expect(store.as(Textus::Role::DEFAULT).get("proposals.draft")).to be_nil
  end

  it "rejects non-authority callers with guard_failed naming the predicate" do
    expect { store.as("agent").reject("proposals.draft") }
      .to fail_guard_with("author_held")
  end

  it "rejects entries that are not in a proposal zone" do
    expect { store.as("human").reject("identity.target") }
      .to raise_error(Textus::ProposalError, /not in a proposal zone/)
  end
end
