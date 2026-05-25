require "spec_helper"

RSpec.describe Textus::Manifest::Rules do
  let(:raw) do
    [
      { "match" => "intake.**",       "handler_allowlist" => ["http_get"] },
      { "match" => "intake.news.*",   "refresh" => { "ttl" => "6h", "on_stale" => "sync" } },
      { "match" => "review.**", "promote_requires" => ["schema_valid"] },
    ]
  end

  let(:rules) { described_class.parse(raw) }

  describe "#for(key)" do
    it "merges all matching rules into one RuleSet, most-specific per slot" do
      set = rules.for("intake.news.hn")
      expect(set.refresh).to be_a(Textus::Domain::Policy::Refresh)
      expect(set.refresh.ttl_seconds).to eq(6 * 3600)
      expect(set.handler_allowlist).to be_a(Textus::Domain::Policy::HandlerAllowlist)
      expect(set.handler_allowlist.allows?("http_get")).to be(true)
      expect(set.promote).to be_nil
    end

    it "returns an empty set for keys not matched by any rule" do
      set = rules.for("identity.something")
      expect(set.refresh).to be_nil
      expect(set.handler_allowlist).to be_nil
      expect(set.promote).to be_nil
    end

    it "respects specificity: a more-specific block overrides a less-specific one per slot" do
      raw2 = [
        { "match" => "intake.**",     "refresh" => { "ttl" => "1d", "on_stale" => "warn" } },
        { "match" => "intake.news.*", "refresh" => { "ttl" => "6h", "on_stale" => "sync" } },
      ]
      set = described_class.parse(raw2).for("intake.news.hn")
      expect(set.refresh.ttl_seconds).to eq(6 * 3600)
      expect(set.refresh.on_stale).to eq(:sync)
    end
  end
end
