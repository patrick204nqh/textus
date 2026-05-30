require "spec_helper"

RSpec.describe Textus::Domain::Policy::Predicates::AcceptSigned do
  let(:policy) { instance_double(Textus::Manifest::Policy) }
  let(:manifest) { instance_double(Textus::Manifest, policy: policy) }

  def eval_for(role)
    Textus::Domain::Policy::Evaluation.new(
      actor: role, transition: :accept, origin: nil,
      target: "working.notes.x", envelope: nil, snapshot: manifest
    )
  end

  it "exposes the canonical predicate name" do
    expect(described_class.new.name).to eq("accept_signed")
  end

  it "passes when the actor holds the 'accept' capability" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return(["human"])
    pred = described_class.new
    expect(pred.call(eval_for("human"))).to be(true)
    expect(pred.reason).to be_nil
  end

  it "passes when the accept holder is a renamed role" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return(["owner"])
    expect(described_class.new.call(eval_for("owner"))).to be(true)
  end

  it "fails and sets reason for an actor without 'accept' (no bespoke #error — folds into GuardFailed)" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return(["human"])
    pred = described_class.new
    expect(pred.call(eval_for("agent"))).to be(false)
    expect(pred.reason).to match(/lacks the 'accept' capability/)
    expect(pred).not_to respond_to(:error)
  end

  it "fails with a disabled message when no role holds 'accept'" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return([])
    pred = described_class.new
    expect(pred.call(eval_for("human"))).to be(false)
    expect(pred.reason).to match(/no role holds the 'accept' capability/)
  end
end
