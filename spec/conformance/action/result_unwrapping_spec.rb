RSpec.describe "Action Result unwrapping" do
  it "unwraps Success results and returns the value" do
    expect(Textus::Value::Result.unwrap(Dry::Monads::Success("ok"))).to eq("ok")
  end

  it "raises ActionError for Failure results" do
    failure = Dry::Monads::Failure(code: :not_found, message: "not here", details: { key: "x" })
    expect { Textus::Value::Result.unwrap(failure) }
      .to raise_error(Textus::ActionError, /not here/)
  end

  it "passes through non-Result return values unchanged" do
    expect(Textus::Value::Result.unwrap("plain string")).to eq("plain string")
    expect(Textus::Value::Result.unwrap({ key: "value" })).to eq({ key: "value" })
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
