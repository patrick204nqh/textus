require "spec_helper"

RSpec.describe Textus::Manifest::Rules do
  let(:raw) do
    [
      { "match" => "intake.**",       "intake_handler_allowlist" => ["http_get"] },
      { "match" => "intake.news.*",   "fetch" => { "ttl" => "6h", "on_stale" => "sync" } },
      { "match" => "review.**", "guard" => { "accept" => ["schema_valid"] } },
    ]
  end

  let(:rules) { described_class.parse(raw) }

  describe "#for(key)" do
    it "merges all matching rules into one RuleSet, most-specific per slot" do
      set = rules.for("intake.news.hn")
      expect(set.fetch).to be_a(Textus::Domain::Policy::Fetch)
      expect(set.fetch.ttl_seconds).to eq(6 * 3600)
      expect(set.handler_allowlist).to be_a(Textus::Domain::Policy::HandlerAllowlist)
      expect(set.handler_allowlist.allows?("http_get")).to be(true)
      expect(set.guard).to be_nil
    end

    it "returns an empty set for keys not matched by any rule" do
      set = rules.for("identity.something")
      expect(set.fetch).to be_nil
      expect(set.handler_allowlist).to be_nil
      expect(set.guard).to be_nil
    end

    it "respects specificity: a more-specific block overrides a less-specific one per slot" do
      raw2 = [
        { "match" => "intake.**",     "fetch" => { "ttl" => "1d", "on_stale" => "warn" } },
        { "match" => "intake.news.*", "fetch" => { "ttl" => "6h", "on_stale" => "sync" } },
      ]
      set = described_class.parse(raw2).for("intake.news.hn")
      expect(set.fetch.ttl_seconds).to eq(6 * 3600)
      expect(set.fetch.on_stale).to eq(:sync)
    end

    describe "intake_handler_allowlist" do
      it "reads intake_handler_allowlist: from rule hash" do
        raw = [{ "match" => "intake.x.*", "intake_handler_allowlist" => ["ical-events"] }]
        set = described_class.parse(raw).for("intake.x.cal")
        expect(set.handler_allowlist.allows?("ical-events")).to be true
      end
    end

    describe "fetch_timeout_seconds" do
      it "parses fetch_timeout_seconds: from a fetch block" do
        raw = [{ "match" => "intake.slow.**", "fetch" => { "ttl" => "1h", "on_stale" => "sync", "fetch_timeout_seconds" => 600 } }]
        set = described_class.parse(raw).for("intake.slow.thing")
        expect(set.fetch.fetch_timeout_seconds).to eq(600)
      end

      it "defaults fetch_timeout_seconds to nil when omitted" do
        raw = [{ "match" => "intake.x.*", "fetch" => { "ttl" => "1h", "on_stale" => "warn" } }]
        set = described_class.parse(raw).for("intake.x.y")
        expect(set.fetch.fetch_timeout_seconds).to be_nil
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
