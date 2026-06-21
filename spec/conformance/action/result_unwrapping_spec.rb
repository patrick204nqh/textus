RSpec.describe "Action Result unwrapping" do
  let(:gate) { Textus::Gate.new(nil) }

  it "unwraps Success results and returns the value" do
    expect(gate.send(:unwrap_result, Dry::Monads::Success("ok"))).to eq("ok")
  end

  it "raises ActionError for Failure results" do
    failure = Dry::Monads::Failure(code: :not_found, message: "not here", details: { key: "x" })
    expect { gate.send(:unwrap_result, failure) }
      .to raise_error(Textus::ActionError, /not here/)
  end

  it "passes through non-Result return values unchanged" do
    expect(gate.send(:unwrap_result, "plain string")).to eq("plain string")
    expect(gate.send(:unwrap_result, { key: "value" })).to eq({ key: "value" })
  end

  context "with a real store" do
    include_context "textus_store_fixture"

    let(:store) do
      store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
        version: textus/4
        lanes:
          - { name: knowledge, kind: canon }
      YAML
    end

    it "Pulse action returns a Success and Gate unwraps it" do
      result = store.gate.dispatch(
        spec: Textus::Action::Pulse.contract,
        inputs: {},
        role: "human",
      )
      expect(result).to be_a(Hash)
      expect(result).to have_key("cursor")
    end
  end
end
