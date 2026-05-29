require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Write::Accept do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones/working/network/org"))
    FileUtils.mkdir_p(File.join(textus_dir, "zones/review"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: owner,    kind: accept_authority }
        - { name: proposer, kind: proposer }
      zones:
        - { name: working, kind: origin, write_policy: [owner, proposer] }
        - { name: review,  kind: origin, write_policy: [proposer, owner] }
      entries:
        - { key: working.network.org, path: working/network/org, zone: working, schema: null, owner: o, nested: true, kind: nested}

        - { key: review,             path: review,             zone: review, schema: null, owner: o, nested: true, kind: nested}

    YAML
    Textus::Store.new(textus_dir)
  end

  context "with a renamed accept_authority role" do
    it "lets the renamed accept_authority role accept proposals" do
      Dir.mktmpdir do |root|
        store = build_store(File.join(root, ".textus"))
        store.as("proposer").put(
          "review.2026-05-19-add-bob",
          meta: {
            "name" => "2026-05-19-add-bob",
            "proposal" => { "target_key" => "working.network.org.bob", "action" => "put" },
            "frontmatter" => { "name" => "bob", "org" => "acme" },
          },
          body: "Proposed",
        )

        ctx = test_ctx(role: "owner")
        result = build_accept(store, ctx).call("review.2026-05-19-add-bob")

        expect(result["target_key"]).to eq("working.network.org.bob")
        expect(result["accepted"]).to eq("review.2026-05-19-add-bob")
      end
    end

    it "rejects callers whose role does not have accept_authority kind, using the configured name" do
      Dir.mktmpdir do |root|
        store = build_store(File.join(root, ".textus"))
        store.as("proposer").put(
          "review.foo",
          meta: {
            "name" => "foo",
            "proposal" => { "target_key" => "working.network.org.x", "action" => "put" },
            "frontmatter" => { "name" => "x" },
          },
          body: "",
        )

        ctx = test_ctx(role: "proposer")
        expect { build_accept(store, ctx).call("review.foo") }
          .to raise_error(Textus::ProposalError, /only owner role can accept/)
      end
    end
  end
end
