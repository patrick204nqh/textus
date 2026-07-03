RSpec.describe Textus::Human::Handlers do
  describe ".propose" do
    it "writes to the proposal zone with prefixed key" do
      container = instance_double("Container")
      manifest = instance_double("Manifest", policy: instance_double("Policy"), resolver: instance_double("Resolver"))
      writer = instance_double("Writer")
      allow(container).to receive_messages(manifest:, writer:)
      allow(manifest.policy).to receive(:propose_lane_for).with("human").and_return("proposals")
      entry = instance_double("Entry", entry: instance_double("Mentry"))
      allow(manifest.resolver).to receive(:resolve).with("proposals.decisions.feature-x").and_return(entry)
      env = instance_double("Envelope")
      allow(env).to receive(:to_h_for_wire).and_return({ "key" => "proposals.decisions.feature-x", "uid" => "abc" })
      allow(writer).to receive(:put).and_return(env)

      call = instance_double("Call", role: "human", correlation_id: "abc")

      result = described_class.propose(
        key: "decisions.feature-x", meta: { "proposal" => { "target_key" => "knowledge.foo" } },
        body: "some body", content: nil, container:, call:
      )

      expect(writer).to have_received(:put).with(
        "proposals.decisions.feature-x",
        mentry: entry.entry,
        call:,
        payload: instance_of(Textus::Value::Payload)
      )
      expect(result).to eq({ "key" => "proposals.decisions.feature-x", "uid" => "abc" })
    end

    it "returns error when role has no propose lane" do
      container = instance_double("Container")
      manifest = instance_double("Manifest", policy: instance_double("Policy"))
      allow(container).to receive(:manifest).and_return(manifest)
      allow(manifest.policy).to receive(:propose_lane_for).with("viewer").and_return(nil)

      call = instance_double("Call", role: "viewer", correlation_id: "abc")

      result = described_class.propose(
        key: "test", container:, call:
      )

      expect(result).to have_key(:error)
      expect(result[:error][:code]).to eq("propose_forbidden")
    end
  end
end
