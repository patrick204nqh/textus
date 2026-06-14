require "spec_helper"

RSpec.describe Textus::Surfaces::RoleScope do
  describe "dispatch routing through gate" do
    include_context "textus_store_fixture"

    let(:store) { minimal_store(root) }
    let(:scope) { store.as("human") }

    it "get routes through gate and returns envelope" do
      store.as("human").put("knowledge.foo", body: "hello")

      result = scope.get("knowledge.foo")
      expect(result).to be_a(Textus::Envelope)
      expect(result.key).to eq("knowledge.foo")
    end

    it "put routes through gate, writes entry, returns envelope" do
      result = scope.put("knowledge.foo", body: "world")

      expect(result).to be_a(Textus::Envelope)
      expect(result.key).to eq("knowledge.foo")
    end

    it "unauthorized put raises WriteForbidden through gate" do
      expect { store.as("agent").put("knowledge.foo", body: "x") }
        .to raise_error(Textus::WriteForbidden)
    end
  end
end
