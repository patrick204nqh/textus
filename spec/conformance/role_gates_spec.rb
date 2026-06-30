require "spec_helper"

# Conformance fixture B from textus/4 §12: role gate on write.
RSpec.describe "textus/4 conformance — Fixture B: role gate on write" do
  include_context "textus/4 conformance fixture"

  describe "Fixture B — role gate on write" do
    it "raises WriteForbidden when an agent tries to write identity" do
      expect do
        store.with_role("agent").entry(:put, key: "identity.self",
                                             meta: { "name" => "self" }, body: "n/a")
      end.to raise_error(Textus::WriteForbidden) do |err|
        env = err.to_envelope
        expect(env["code"]).to eq("write_forbidden")
        expect(env["details"]["lane"]).to eq("identity")
      end
    end
  end
end
