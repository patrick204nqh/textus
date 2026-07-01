require "spec_helper"

RSpec.describe "Manifest::Rules#for_with_trace" do
  let(:rules) do
    Textus::Manifest::Rules.parse([
                                    { "match" => "decisions.*", "guard" => { "write" => ["admin"] } },
                                    { "match" => "*" },
                                    { "match" => "knowledge.*" },
                                  ])
  end

  describe Textus::Manifest::TriggerCatalog do
    it "rejects unknown trigger tokens" do
      expect do
        described_class.validate_trigger!("entry.unknown")
      end.to raise_error(Textus::BadManifest, /unknown trigger: entry\.unknown/)
    end
  end

  describe "#for_with_trace" do
    let(:key) { "decisions.adr-0001" }
    let(:result) { rules.for_with_trace(key) }
    let(:ruleset) { result.first }
    let(:trace)   { result.last }

    it "returns a RuleSet and RuleTrace with correct key, matched candidates, and winners" do
      expect(result.size).to eq(2)
      expect(ruleset).to be_a(Textus::Manifest::Rules::RuleSet)
      expect(trace).to be_a(Textus::Manifest::RuleTrace)
      expect(trace.key).to eq(key)
      expect(trace.candidates.size).to eq(3)
      expect(trace.winners.map { |w| w["pattern"] }).to eq(["decisions.*"])
    end

    it "marks only matching candidates with matched=true and non-matching with specificity=0" do
      decisions = trace.candidates.find { |c| c["pattern"] == "decisions.*" }
      star      = trace.candidates.find { |c| c["pattern"] == "*" }
      knowledge = trace.candidates.find { |c| c["pattern"] == "knowledge.*" }
      expect(decisions["matched"]).to be(true)
      expect(star["matched"]).to be(false)
      expect(knowledge["matched"]).to be(false)
      expect(knowledge["specificity"]).to eq(0)
    end

    it "ruleset_fields matches RuleSet from for(key)" do
      expected_ruleset = rules.for(key)
      expect(trace.ruleset_fields).to eq(expected_ruleset.to_h)
      via_for = rules.for(key)
      via_trace, = rules.for_with_trace(key)
      expect(via_for).to eq(via_trace)
    end
  end
end
