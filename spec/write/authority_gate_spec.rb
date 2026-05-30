require "spec_helper"

RSpec.describe Textus::Write::AuthorityGate do
  # Minimal host exposing the @manifest/@call ivars the gate reads, so we can
  # exercise assert_accept_authority! in isolation from Accept/Reject (whose
  # fixtures migrate to the capability shape in a later task).
  let(:host_class) do
    Class.new do
      include Textus::Write::AuthorityGate

      def initialize(manifest:, call:)
        @manifest = manifest
        @call = call
      end
    end
  end

  let(:policy) { instance_double(Textus::Manifest::Policy) }
  let(:manifest) { instance_double(Textus::Manifest, policy: policy) }

  def host_for(role)
    call = instance_double(Textus::Call, role: role)
    host_class.new(manifest: manifest, call: call)
  end

  it "passes when the caller holds the accept capability" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return(["human"])
    expect { host_for("human").assert_accept_authority!("accept") }.not_to raise_error
  end

  it "raises ProposalError naming the accept-holder when the caller lacks it" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return(["human"])
    expect { host_for("agent").assert_accept_authority!("accept") }
      .to raise_error(Textus::ProposalError, /only human role can accept proposals; got 'agent'/)
  end

  it "raises the 'no role holds the accept capability' variant when none declared" do
    allow(policy).to receive(:roles_with_capability).with("accept").and_return([])
    expect { host_for("agent").assert_accept_authority!("reject") }
      .to raise_error(Textus::ProposalError, /no role holds the accept capability.*reject is disabled/)
  end
end
