require "spec_helper"

# Conformance fixture C from textus/3 §12: schema validation.
RSpec.describe "textus/3 conformance — Fixture C: schema validation" do
  include_context "textus/3 conformance fixture"

  describe "Fixture C — schema validation" do
    it "raises SchemaViolation listing the missing required field" do
      expect do
        store.as("human").put(
          "knowledge.network.org.bob",
          meta: { "name" => "bob", "org" => "acme" },
          body: "",
        )
      end.to raise_error(Textus::SchemaViolation) do |err|
        env = err.to_envelope
        expect(env["code"]).to eq("schema_violation")
        expect(env["details"]["missing"]).to eq(["relationship"])
        expect(err.exit_code).to eq(1)
      end
    end
  end
end
