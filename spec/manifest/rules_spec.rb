require "spec_helper"

RSpec.describe Textus::Manifest::Rules do
  let(:raw) do
    [
      { "match" => "intake.**",       "intake_handler_allowlist" => ["http_get"] },
      { "match" => "intake.news.*",   "lifecycle" => { "ttl" => "6h", "on_expire" => "refresh" } },
      { "match" => "review.**", "guard" => { "accept" => ["schema_valid"] } },
    ]
  end

  let(:rules) { described_class.parse(raw) }

  describe "#for(key)" do
    it "merges all matching rules into one RuleSet, most-specific per slot" do
      set = rules.for("intake.news.hn")
      expect(set.lifecycle).to be_a(Textus::Domain::Policy::Lifecycle)
      expect(set.lifecycle.ttl_seconds).to eq(6 * 3600)
      expect(set.handler_allowlist).to be_a(Textus::Domain::Policy::HandlerAllowlist)
      expect(set.handler_allowlist.allows?("http_get")).to be(true)
      expect(set.guard).to be_nil
    end

    it "returns an empty set for keys not matched by any rule" do
      set = rules.for("identity.something")
      expect(set.lifecycle).to be_nil
      expect(set.handler_allowlist).to be_nil
      expect(set.guard).to be_nil
    end

    it "respects specificity: a more-specific block overrides a less-specific one per slot" do
      raw2 = [
        { "match" => "intake.**",     "lifecycle" => { "ttl" => "1d", "on_expire" => "warn" } },
        { "match" => "intake.news.*", "lifecycle" => { "ttl" => "6h", "on_expire" => "refresh" } },
      ]
      set = described_class.parse(raw2).for("intake.news.hn")
      expect(set.lifecycle.ttl_seconds).to eq(6 * 3600)
      expect(set.lifecycle.on_expire).to eq(:refresh)
    end

    describe "intake_handler_allowlist" do
      it "reads intake_handler_allowlist: from rule hash" do
        raw = [{ "match" => "intake.x.*", "intake_handler_allowlist" => ["ical-events"] }]
        set = described_class.parse(raw).for("intake.x.cal")
        expect(set.handler_allowlist.allows?("ical-events")).to be true
      end
    end

    describe "guard" do
      it "parses guard: { accept: [...] }" do
        raw = [{ "match" => "review.**", "guard" => { "accept" => ["schema_valid"] } }]
        set = described_class.parse(raw).for("review.x")
        expect(set.guard).to eq({ "accept" => ["schema_valid"] })
      end
    end
  end
end
