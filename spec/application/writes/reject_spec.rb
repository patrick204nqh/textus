require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Reject do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, write_policy: [human] }
        - { name: review, write_policy: [agent, human] }
      entries:
        - { key: identity.target, path: target.md, zone: identity, schema: null, owner: o }
        - { key: review.draft, path: draft.md, zone: review, schema: null, owner: o }
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
      store.bus.register(:proposal_rejected, :capture_reject) { |key:, target_key:, **| events << [key, target_key] }

      ctx = test_ctx(role: "human")
      res = build_reject(store, ctx).call("review.draft")

      expect(res).to include("protocol" => Textus::PROTOCOL, "rejected" => "review.draft", "target_key" => "identity.target")
      expect(events).to eq([["review.draft", "identity.target"]])
      expect(Textus::Operations.for(store).get("review.draft")).to be_nil
    end
  end

  it "rejects non-human callers" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      ctx = test_ctx(role: "agent")
      expect { build_reject(store, ctx).call("review.draft") }
        .to raise_error(Textus::ProposalError, /only human role can reject/)
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
