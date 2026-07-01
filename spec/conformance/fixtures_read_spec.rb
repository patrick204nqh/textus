require "spec_helper"
require "digest"

# Conformance fixture A from textus/4 §12: resolve and read.
RSpec.describe "textus/4 conformance — Fixture A: resolve and read" do
  include_context "textus/4 conformance fixture"

  describe "Fixture A — resolve and read" do
    it "returns the canonical envelope with a matching sha256 etag" do
      env = store.with_role(Textus::Value::Role::DEFAULT).get(key: "knowledge.network.org.jane")

      aggregate_failures do
        expect(env.protocol).to eq("textus/4")
        expect(env.key).to eq("knowledge.network.org.jane")
        expect(env.lane).to eq("knowledge")
        expect(env.owner).to eq("human:patrick")
        expect(File.absolute_path?(env.path)).to be true
        expect(env.path).to end_with("knowledge/network/org/jane.md")

        expect(env.meta).to eq(
          "name" => "jane", "relationship" => "peer", "org" => "acme",
        )
        expect(env.body).to include("Short body in Markdown.")

        expected = "sha256:#{Digest::SHA256.hexdigest(File.binread(env.path))}"
        expect(env.etag).to eq(expected)
        expect(env.schema_ref).to eq("person")
      end
    end
  end
end
