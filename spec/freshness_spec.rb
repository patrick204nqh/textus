require "spec_helper"

RSpec.describe Textus::Freshness do
  describe ".evaluate" do
    let(:mentry) do
      instance_double(Textus::Manifest::Entry, intake_handler: "news_handler", ttl: "300s", on_stale: :warn)
    end

    it "returns :fresh when ttl is nil" do
      m = instance_double(Textus::Manifest::Entry, intake_handler: nil, ttl: nil, on_stale: :warn)
      envelope = { "_meta" => { "last_refreshed_at" => Time.now.utc.iso8601 } }
      expect(Textus::Freshness.evaluate(m, envelope)).to eq(:fresh)
    end

    it "returns :fresh when last_refreshed_at + ttl > now" do
      envelope = { "_meta" => { "last_refreshed_at" => (Time.now - 60).utc.iso8601 } }
      expect(Textus::Freshness.evaluate(mentry, envelope)).to eq(:fresh)
    end

    it "returns a stale hash when last_refreshed_at + ttl < now" do
      envelope = { "_meta" => { "last_refreshed_at" => (Time.now - 600).utc.iso8601 } }
      result = Textus::Freshness.evaluate(mentry, envelope)
      expect(result).to be_a(Hash)
      expect(result[:stale]).to be(true)
      expect(result[:reason]).to match(/ttl exceeded/)
    end

    it "returns a stale hash when last_refreshed_at is missing" do
      envelope = { "_meta" => {} }
      result = Textus::Freshness.evaluate(mentry, envelope)
      expect(result[:stale]).to be(true)
      expect(result[:reason]).to match(/never refreshed/)
    end
  end
end
