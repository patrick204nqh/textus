require "spec_helper"

RSpec.describe Textus::Domain::Policy::Predicates::ZoneWritableBy do
  let(:mentry)     { instance_double(Textus::Manifest::Entry::Base, zone: "working", key: "working.notes") }
  let(:resolution) { instance_double(Textus::Manifest::Resolver::Resolution, entry: mentry) }
  let(:resolver)   { instance_double(Textus::Manifest::Resolver, resolve: resolution) }
  let(:permission) { instance_double(Textus::Domain::Permission) }
  let(:policy)     { instance_double(Textus::Manifest::Policy) }
  let(:manifest)   { instance_double(Textus::Manifest, resolver: resolver, policy: policy) }

  def eval_for(role)
    Textus::Domain::Policy::Evaluation.new(
      actor: role, transition: :put, origin: nil,
      target: "working.notes", envelope: nil, snapshot: manifest
    )
  end

  before { allow(policy).to receive(:permission_for).with("working").and_return(permission) }

  it "passes when the role may write the target's zone" do
    allow(permission).to receive(:allows_write?).with("human").and_return(true)
    expect(described_class.new.call(eval_for("human"))).to be(true)
  end

  it "fails for a role lacking the zone-kind's verb and raises WriteForbidden via #error" do
    allow(permission).to receive(:allows_write?).with("agent").and_return(false)
    allow(policy).to receive(:verb_for_zone).with("working").and_return("accept")
    allow(policy).to receive(:roles_with_capability).with("accept").and_return(["human"])

    pred = described_class.new
    e = eval_for("agent") # working is origin → needs 'accept'; agent lacks it
    expect(pred.call(e)).to be(false)
    expect { raise pred.error(e) }.to raise_error(Textus::WriteForbidden) do |err|
      expect(err.code).to eq("write_forbidden")
      expect(err.message).to match(/capability 'accept'/)
    end
  end
end
