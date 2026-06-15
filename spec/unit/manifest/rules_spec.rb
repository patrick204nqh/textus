require "spec_helper"

RSpec.describe Textus::Manifest::Rules do
  let(:raw) do
    [
      { "match" => "intake.news.*",   "retention" => { "ttl" => "6h", "action" => "drop" } },
      { "match" => "review.**", "guard" => { "accept" => ["schema_valid"] } },
    ]
  end

  let(:rules) { described_class.parse(raw) }

  describe "#for(key)" do
    it "merges all matching rules into one RuleSet, most-specific per slot" do
      set = rules.for("intake.news.hn")
      expect(set.retention.ttl_seconds).to eq(6 * 3600)
      expect(set.retention.action).to eq(:drop)
      expect(set.guard).to be_nil
    end

    it "returns an empty set for keys not matched by any rule" do
      set = rules.for("identity.something")
      expect(set.retention).to be_nil
      expect(set.guard).to be_nil
    end

    it "respects specificity: a more-specific block overrides a less-specific one per slot" do
      raw2 = [
        { "match" => "intake.**",     "retention" => { "ttl" => "1d", "action" => "archive" } },
        { "match" => "intake.news.*", "retention" => { "ttl" => "6h", "action" => "drop" } },
      ]
      set = described_class.parse(raw2).for("intake.news.hn")
      expect(set.retention.ttl_seconds).to eq(6 * 3600)
      expect(set.retention.action).to eq(:drop)
    end

    describe "guard" do
      it "parses guard: { accept: [...] }" do
        raw = [{ "match" => "review.**", "guard" => { "accept" => ["schema_valid"] } }]
        set = described_class.parse(raw).for("review.x")
        expect(set.guard).to eq({ "accept" => ["schema_valid"] })
      end
    end

    describe "retention" do
      it "parses retention: { ttl, action } into a Retention policy" do
        rules = described_class.parse([{ "match" => "feeds.*", "retention" => { "ttl" => "6h", "action" => "archive" } }])
        ret = rules.for("feeds.x").retention
        expect(ret.action).to eq(:archive)
        expect(ret.ttl_seconds).to eq(6 * 3600)
      end

      it "leaves retention nil when the slot is absent" do
        rules = described_class.parse([{ "match" => "artifacts.*", "guard" => {} }])
        expect(rules.for("artifacts.x").retention).to be_nil
      end
    end
  end
end
