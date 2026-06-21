RSpec.describe Textus::Surface::Projector do
  subject(:projector) { described_class.new(view_key: :default, binder_method: :inputs_from_wire) }

  it "defaults to :default view_key and :inputs_from_wire binder" do
    expect(projector).to be_a(described_class)
  end

  describe "#names" do
    it "returns verb names for contract-bearing actions" do
      names = projector.names
      expect(names).to include("get", "put", "list", "pulse")
    end

    it "filters by a given verb map" do
      fake = { get: double(contract?: true, contract: nil) }
      expect(projector.names(fake)).to eq(["get"])
    end

    it "skips actions without a contract" do
      fake = { foo: double(respond_to?: false) }
      expect(projector.names(fake)).to be_empty
    end
  end

  describe "#verbs" do
    it "returns contract-bearing actions" do
      verbs = projector.verbs
      expect(verbs).to have_key(:get)
      expect(verbs).not_to have_key(:nonexistent)
    end
  end

  describe "#dispatch" do
    let(:klass) { Textus::Action::VERBS[:pulse] }
    let(:spec) { klass.contract }

    it "dispatches via the Gate and applies the view" do
      store = instance_double(Textus::Store, gate: instance_double(Textus::Gate))
      allow(store.gate).to receive(:dispatch).and_return("cursor" => 0, "changed" => [])
      result = projector.dispatch("pulse", inputs: {}, store:, role: "human")
      expect(result).to have_key("cursor")
    end

    it "raises KeyError for unknown verbs" do
      store = instance_double(Textus::Store)
      expect {
        projector.dispatch("nope", inputs: {}, store:, role: "human")
      }.to raise_error(KeyError)
    end
  end
end
