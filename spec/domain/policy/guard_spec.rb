require "spec_helper"

RSpec.describe Textus::Domain::Policy::Guard do
  # Minimal fake predicates
  def pred(name, passes, reason: nil, error: nil)
    Class.new do
      define_method(:name) { name }
      define_method(:call) { |_eval| passes }
      define_method(:reason) { reason }
      define_method(:error) { |_e| error } if error
    end.new
  end

  let(:eval) do
    Textus::Domain::Policy::Evaluation.new(
      actor: "agent", transition: :put, origin: nil,
      target: "working.x", envelope: nil, manifest: nil
    )
  end

  it "passes when all predicates pass" do
    g = described_class.new([pred("a", true), pred("b", true)])
    expect { g.check!(eval) }.not_to raise_error
  end

  it "short-circuits to a predicate's bespoke #error" do
    boom = Textus::WriteForbidden.new("working.x", "working", verb: "accept", holders: ["human"])
    g = described_class.new([pred("zone_writable_by", false, error: boom), pred("b", true)])
    expect { g.check!(eval) }.to raise_error(Textus::WriteForbidden)
  end

  it "accumulates failures without bespoke errors into GuardFailed" do
    g = described_class.new([
                              pred("schema_valid", false, reason: "missing field x"),
                              pred("fresh_within", false, reason: "too old"),
                            ])
    expect { g.check!(eval) }.to raise_error(Textus::GuardFailed) do |err|
      expect(err.code).to eq("guard_failed")
      expect(err.details["failed"]).to eq([
                                            { "predicate" => "schema_valid", "reason" => "missing field x" },
                                            { "predicate" => "fresh_within", "reason" => "too old" },
                                          ])
    end
  end

  it "explain returns [name, ok, reason] for each predicate" do
    g = described_class.new([pred("a", true), pred("b", false, reason: "nope")])
    expect(g.explain(eval)).to eq([["a", true, nil], ["b", false, "nope"]])
  end
end
