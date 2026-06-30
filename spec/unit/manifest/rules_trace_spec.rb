require "spec_helper"

RSpec.describe "Manifest::Rules#for_with_trace" do
  let(:rules) do
    Textus::Manifest::Rules.parse([
                                    { "match" => "decisions.*", "guard" => { "write" => ["admin"] } },
                                    { "match" => "*" },
                                    { "match" => "knowledge.*" },
                                  ])
  end

  describe "RuleTrace" do
    it "is a Data.define with key, candidates, winners, ruleset_fields" do
      expect(Textus::Manifest::RuleTrace.members).to contain_exactly(
        :key, :candidates, :winners, :ruleset_fields
      )
    end
  end

  describe "#for_with_trace" do
    let(:key) { "decisions.adr-0001" }
    let(:result) { rules.for_with_trace(key) }
    let(:ruleset) { result.first }
    let(:trace)   { result.last }

    it "returns a two-element array [RuleSet, RuleTrace]" do
      expect(result.size).to eq(2)
      expect(ruleset).to be_a(Textus::Manifest::Rules::RuleSet)
      expect(trace).to be_a(Textus::Manifest::RuleTrace)
    end

    it "trace.key equals the queried key" do
      expect(trace.key).to eq(key)
    end

    it "candidates covers every rule block incl. non-matching ones" do
      expect(trace.candidates.size).to eq(3)
      decisions = trace.candidates.find { |c| c["pattern"] == "decisions.*" }
      star      = trace.candidates.find { |c| c["pattern"] == "*" }
      knowledge = trace.candidates.find { |c| c["pattern"] == "knowledge.*" }
      expect(decisions["matched"]).to be(true)
      expect(star["matched"]).to be(false)
      expect(knowledge["matched"]).to be(false)
    end

    it "specificity is 0 for non-matching candidates" do
      knowledge = trace.candidates.find { |c| c["pattern"] == "knowledge.*" }
      expect(knowledge["specificity"]).to eq(0)
    end

    it "winners contains only matched blocks sorted by specificity" do
      expect(trace.winners.map { |w| w["pattern"] }).to eq(["decisions.*"])
    end

    it "winners preserve field data for in_pick fields" do
      decisions = trace.winners.first
      expect(decisions["fields"]["guard"]).to eq({ "write" => ["admin"] })
    end

    it "ruleset_fields matches RuleSet from for(key)" do
      expected_ruleset = rules.for(key)
      expect(trace.ruleset_fields).to eq(expected_ruleset.to_h)
    end

    it "for(key) returns same RuleSet as for_with_trace(key).first (non-regression)" do
      via_for = rules.for(key)
      via_trace, = rules.for_with_trace(key)
      expect(via_for).to eq(via_trace)
    end
  end
end
