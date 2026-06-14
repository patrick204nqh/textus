require "spec_helper"

# WS3: FIELD_REGISTRY is the single source of truth for the rule-block field
# set. These tests pin the single-source property — every downstream
# enumeration derives from the registry, so adding a field is a one-file edit —
# and the materialize-visibility fix (materialize was resolved by pick() yet
# invisible to rule_list / rule_explain / doctor; it is now surfaced).
RSpec.describe Textus::Manifest::Schema do
  let(:registry) { Textus::Manifest::Schema::FIELD_REGISTRY }

  describe "single source of truth" do
    it "drives Schema::RULE_KEYS (match + every field's yaml_key, in order)" do
      expect(Textus::Manifest::Schema::RULE_KEYS).to eq(
        ["match"] + registry.values.map { |m| m[:yaml_key] },
      )
    end

    it "drives the RuleSet members (the in_pick fields)" do
      expect(Textus::Manifest::Rules::RuleSet.members).to eq(
        registry.select { |_, m| m[:in_pick] }.keys,
      )
    end

    it "drives doctor RuleAmbiguity SLOTS (the in_ambiguity fields)" do
      expect(Textus::Doctor::Check::RuleAmbiguity::SLOTS).to eq(
        registry.select { |_, m| m[:in_ambiguity] }.keys,
      )
    end

    it "drives Read::RuleList field membership (the in_rule_list fields)" do
      expect(Textus::Action::RuleList::LIST_FIELDS).to eq(
        registry.select { |_, m| m[:in_rule_list] }.keys,
      )
    end

    it "exposes a Block attr_reader for every field" do
      block = Textus::Manifest::Rules::Block.new("match" => "x")
      registry.each_key { |field| expect(block).to respond_to(field) }
    end
  end

  describe "retention field (ADR 0093)" do
    it "is in the registry and participates in all surfaces" do
      meta = registry.fetch(:retention)
      expect(meta[:in_pick]).to be(true)
      expect(meta[:in_ambiguity]).to be(true)
      expect(meta[:in_rule_list]).to be(true)
      expect(meta[:in_rule_explain]).to include(:lean, :detail)
    end

    it "keeps retention as the only cadence/GC field while allowing reaction policy" do
      expect(registry.keys).to eq(%i[handler_permit guard retention react])
    end
  end
end
