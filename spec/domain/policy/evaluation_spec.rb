require "spec_helper"

RSpec.describe Textus::Domain::Policy::Evaluation do
  it "is an immutable value carrying the crossing context" do
    eval = described_class.new(
      actor: "agent", transition: :put, origin: nil,
      target: "working.notes.x", envelope: nil, snapshot: :manifest_stub
    )
    expect(eval.actor).to eq("agent")
    expect(eval.transition).to eq(:put)
    expect(eval.target).to eq("working.notes.x")
    expect(eval.snapshot).to eq(:manifest_stub)
    expect { eval.instance_variable_set(:@actor, "x") }.to raise_error(FrozenError)
  end
end
