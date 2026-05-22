require "spec_helper"

RSpec.describe Textus::Manifest::Policies do
  let(:raw) do
    [
      { "match" => "inbox.**",       "handler_allowlist" => ["http_get"] },
      { "match" => "inbox.news.*",   "refresh" => { "ttl" => "6h", "on_stale" => "sync" } },
      { "match" => "review.**",      "promote_requires" => ["schema_valid"] },
    ]
  end

  let(:policies) { described_class.parse(raw) }

  describe "#for(key)" do
    it "merges all matching rules into one PolicySet, most-specific per slot" do
      set = policies.for("inbox.news.hn")
      expect(set.refresh).to be_a(Textus::Domain::Policy::Refresh)
      expect(set.refresh.ttl_seconds).to eq(6 * 3600)
      expect(set.handler_allowlist).to be_a(Textus::Domain::Policy::HandlerAllowlist)
      expect(set.handler_allowlist.allows?("http_get")).to be(true)
      expect(set.promote).to be_nil
    end

    it "returns an empty set for keys not matched by any rule" do
      set = policies.for("identity.something")
      expect(set.refresh).to be_nil
      expect(set.handler_allowlist).to be_nil
      expect(set.promote).to be_nil
    end

    it "respects specificity: a more-specific block overrides a less-specific one per slot" do
      raw2 = [
        { "match" => "inbox.**",     "refresh" => { "ttl" => "1d", "on_stale" => "warn" } },
        { "match" => "inbox.news.*", "refresh" => { "ttl" => "6h", "on_stale" => "sync" } },
      ]
      set = described_class.parse(raw2).for("inbox.news.hn")
      expect(set.refresh.ttl_seconds).to eq(6 * 3600)
      expect(set.refresh.on_stale).to eq(:sync)
    end
  end
end
