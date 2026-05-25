require "spec_helper"

RSpec.describe Textus::Domain::Policy::Promotion do
  let(:always_true) do
    instance_double(Textus::Domain::Policy::Predicates::SchemaValid,
                    name: "always_true", call: true, reason: nil)
  end
  let(:always_false) do
    instance_double(Textus::Domain::Policy::Predicates::SchemaValid,
                    name: "schema_valid", call: false, reason: "missing field 'name'")
  end

  it "passes when all predicates return true" do
    policy = described_class.new(predicates: [always_true, always_true])
    result = policy.evaluate(entry: nil, store: nil)
    expect(result.ok?).to be true
    expect(result.reasons).to be_empty
  end

  it "fails with concatenated reasons when any predicate is false" do
    policy = described_class.new(predicates: [always_true, always_false])
    result = policy.evaluate(entry: nil, store: nil)
    expect(result.ok?).to be false
    expect(result.reasons.first).to match(/schema_valid.*missing field/)
  end

  it "resolves predicate names from a registry" do
    policy = described_class.from_names(%w[schema_valid human_accept])
    expect(policy.predicate_names).to contain_exactly("schema_valid", "human_accept")
  end

  it "rejects unknown predicate names" do
    expect { described_class.from_names(["mystery"]) }
      .to raise_error(Textus::UsageError, /unknown.*mystery/i)
  end

  describe "always_false double call with named args" do
    it "handles named-arg call correctly" do
      allow(always_false).to receive(:call).with(entry: nil, store: nil).and_return(false)
      policy = described_class.new(predicates: [always_false])
      result = policy.evaluate(entry: nil, store: nil)
      expect(result.ok?).to be false
    end
  end
end
