require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Write::Reject do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: origin }
        - { name: review, kind: queue }
      entries:
        - { key: identity.target, path: target.md, zone: identity, schema: null, owner: o, kind: leaf}

        - { key: review.draft, path: draft.md, zone: review, schema: null, owner: o, kind: leaf}

    YAML
    File.write(File.join(textus_dir, "zones/target.md"), "---\nname: target\n---\nbody\n")
    File.write(
      File.join(textus_dir, "zones/draft.md"),
      "---\nname: draft\nproposal:\n  target_key: identity.target\n---\nbody\n",
    )
    Textus::Store.new(textus_dir)
  end

  it "deletes the proposal and fires :proposal_rejected" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))

      events = []
      store.events.register(:proposal_rejected, :capture_reject) { |key:, target_key:, **| events << [key, target_key] }

      ctx = test_ctx(role: "human")
      res = build_reject(store, ctx).call("review.draft")

      expect(res).to include("protocol" => Textus::PROTOCOL, "rejected" => "review.draft", "target_key" => "identity.target")
      expect(events).to eq([["review.draft", "identity.target"]])
      expect(store.as(Textus::Role::DEFAULT).get("review.draft")).to be_nil
    end
  end

  it "rejects non-authority callers with guard_failed naming the predicate" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = test_ctx(role: "agent")
      expect { build_reject(store, ctx).call("review.draft") }
        .to raise_error(Textus::GuardFailed) do |e|
          expect(e.code).to eq("guard_failed")
          expect(e.details["failed"].map { |f| f["predicate"] }).to include("accept_signed")
        end
    end
  end

  it "rejects entries that are not in a proposal zone" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = test_ctx(role: "human")
      expect { build_reject(store, ctx).call("identity.target") }
        .to raise_error(Textus::ProposalError, /not in a proposal zone/)
    end
  end
end
