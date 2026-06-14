require "spec_helper"

RSpec.describe Textus::Dispatch::Event do
  it "constructs with required fields" do
    event = described_class.new(
      name: "entry.put",
      actor: "human",
      target: "knowledge.foo",
      payload: { key: "knowledge.foo" },
      actions: [],
      correlation_id: "abc-123",
    )

    expect(event.name).to eq("entry.put")
    expect(event.actor).to eq("human")
    expect(event.target).to eq("knowledge.foo")
    expect(event.actions).to eq([])
  end

  it "defaults payload to empty hash and actions to empty array" do
    event = described_class.new(
      name: "entry.get",
      actor: "human",
      target: "knowledge.foo",
      payload: {},
      actions: [],
      correlation_id: nil,
    )

    expect(event.payload).to eq({})
    expect(event.actions).to eq([])
  end

  describe Textus::Dispatch::Catalog::Events do
    it "declares dotted event name constants" do
      expect(described_class::ENTRY_PUT).to eq("entry.put")
      expect(described_class::ENTRY_WRITTEN).to eq("entry.written")
      expect(described_class::STEP_FETCH_COMPLETE).to eq("step.fetch.complete")
    end
  end
end
