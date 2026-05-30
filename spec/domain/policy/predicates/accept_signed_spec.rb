require "spec_helper"

RSpec.describe Textus::Domain::Policy::Predicates::AcceptSigned do
  let(:policy) { instance_double(Textus::Manifest::Policy) }
  let(:manifest) { instance_double(Textus::Manifest, policy: policy) }

  it "exposes the canonical predicate name" do
    expect(described_class.new.name).to eq("accept_signed")
  end

  it "passes when the role holds the accept capability" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return(["human"])
    pred = described_class.new
    expect(pred.call(role: "human", manifest: manifest)).to be true
    expect(pred.reason).to be_nil
  end

  it "passes when the accept holder is a renamed role" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return(["owner"])
    pred = described_class.new
    expect(pred.call(role: "owner", manifest: manifest)).to be true
  end

  it "fails when the role does not hold the accept capability" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return(["human"])
    pred = described_class.new
    expect(pred.call(role: "agent", manifest: manifest)).to be false
    expect(pred.reason).to match(/role 'agent' does not hold the 'accept' capability/)
  end

  it "passes when role is nil/empty (Accept has already gated upstream)" do
    pred = described_class.new
    expect(pred.call(role: nil, manifest: manifest)).to be true
    expect(pred.call(role: "", manifest: manifest)).to be true
  end
end
