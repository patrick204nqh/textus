require "spec_helper"

RSpec.describe Textus::Write::Accept do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[working review], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: owner,    can: [author, propose] }
        - { name: proposer, can: [propose] }
      zones:
        - { name: working, kind: canon }
        - { name: review,  kind: queue }
      entries:
        - { key: working.network.org, path: working/network/org, zone: working, schema: null, owner: o, nested: true, kind: nested}

        - { key: review,             path: review,             zone: review, schema: null, owner: o, nested: true, kind: nested}

    YAML
  end

  context "with a renamed author-capability role" do
    it "lets the renamed author-capability role accept proposals" do
      FileUtils.mkdir_p(File.join(root, "zones/working/network/org"))
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

    it "rejects callers whose role does not hold the author capability, using the configured name" do
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
        .to raise_error(Textus::GuardFailed) do |e|
          expect(e.details["failed"].map { |f| f["predicate"] }).to include("author_signed")
          expect(e.message).to match(/held by: owner/)
        end
    end
  end
end
