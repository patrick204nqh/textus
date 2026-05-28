require "spec_helper"

RSpec.describe Textus::Domain::Policy::Predicates::AcceptAuthoritySigned do
  let(:policy) { instance_double(Textus::Manifest::Policy) }
  let(:manifest) { instance_double(Textus::Manifest, policy: policy) }

  it "exposes the canonical predicate name" do
    expect(described_class.new.name).to eq("accept_authority_signed")
  end

  it "passes when the role has accept_authority kind (default mapping)" do
    allow(policy).to receive(:role_kind).with("human").and_return(:accept_authority)
    pred = described_class.new
    expect(pred.call(role: "human", manifest: manifest)).to be true
    expect(pred.reason).to be_nil
  end

  it "passes when the role has accept_authority kind under a renamed role" do
    allow(policy).to receive(:role_kind).with("owner").and_return(:accept_authority)
    pred = described_class.new
    expect(pred.call(role: "owner", manifest: manifest)).to be true
  end

  it "fails when the role has a non-authority kind, reporting the kind seen" do
    allow(policy).to receive(:role_kind).with("agent").and_return(:proposer)
    pred = described_class.new
    expect(pred.call(role: "agent", manifest: manifest)).to be false
    expect(pred.reason).to match(/role 'agent' has kind ':proposer'.*expected ':accept_authority'/)
  end

  it "passes when role is nil/empty (Accept has already gated by kind upstream)" do
    pred = described_class.new
    expect(pred.call(role: nil, manifest: manifest)).to be true
    expect(pred.call(role: "", manifest: manifest)).to be true
  end
end
