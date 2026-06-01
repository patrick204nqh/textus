require "spec_helper"

RSpec.describe Textus::Write::Accept do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[working review], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose] }
      zones:
        - { name: working, kind: canon }
        - { name: review,  kind: queue }
      entries:
        - { key: working.network.org, path: working/network/org, zone: working, owner: o, kind: nested}

        - { key: review,             path: review,             zone: review, owner: o, kind: nested}

    YAML
  end

  context "with the author capability on human" do
    it "lets the renamed author-capability role accept proposals" do
      FileUtils.mkdir_p(File.join(root, "zones/working/network/org"))
      store.as("agent").put(
        "review.2026-05-19-add-bob",
        meta: {
          "name" => "2026-05-19-add-bob",
          "proposal" => { "target_key" => "working.network.org.bob", "action" => "put" },
          "frontmatter" => { "name" => "bob", "org" => "acme" },
        },
        body: "Proposed",
      )

      result = store.as("human").accept("review.2026-05-19-add-bob")

      expect(result["target_key"]).to eq("working.network.org.bob")
      expect(result["accepted"]).to eq("review.2026-05-19-add-bob")
    end

    it "rejects callers whose role does not hold the author capability, using the configured name" do
      store.as("agent").put(
        "review.foo",
        meta: {
          "name" => "foo",
          "proposal" => { "target_key" => "working.network.org.x", "action" => "put" },
          "frontmatter" => { "name" => "x" },
        },
        body: "",
      )

      expect { store.as("agent").accept("review.foo") }
        .to raise_error(Textus::GuardFailed) do |e|
          expect(e.details["failed"].map { |f| f["predicate"] }).to include("author_held")
          expect(e.message).to match(/held by: human/)
        end
    end
  end
end
