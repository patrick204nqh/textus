require "spec_helper"

# Conformance for textus/3 feeds lifecycle via TTL (freshness).
RSpec.describe "textus/3 conformance — feeds lifecycle via TTL (freshness)" do
  include_context "textus/3 conformance fixture"

  describe "feeds lifecycle via TTL (freshness)" do
    def feeds_row
      store.as(Textus::Role::DEFAULT).freshness(zone: "artifacts")
           .find { |r| r[:key] == "artifacts.feeds.calendar.events" }
    end

    it "marks a never-recorded feeds entry expired" do
      row = feeds_row
      expect(row[:status]).to eq(:expired)
      expect(row[:action]).to eq(:refresh)
    end

    it "marks a feeds entry past its TTL expired" do
      feeds_path = File.join(root, "zones/artifacts/feeds/calendar/events.md")
      # Well past the 300s TTL. Wide margin keeps this deterministic regardless of
      # iso8601 second-truncation in last_fetched_at.
      stale_time = (Time.now - 3600).utc.iso8601
      File.write(feeds_path, <<~MD)
        ---
        name: events
        last_fetched_at: "#{stale_time}"
        ---
        body
      MD
      row = feeds_row
      expect(row[:status]).to eq(:expired)
      expect(row[:next_due_at]).not_to be_nil
    end

    it "marks a feeds entry within its TTL fresh" do
      feeds_path = File.join(root, "zones/artifacts/feeds/calendar/events.md")
      fresh_time = Time.now.utc.iso8601
      File.write(feeds_path, <<~MD)
        ---
        name: events
        last_fetched_at: "#{fresh_time}"
        ---
        body
      MD
      expect(feeds_row[:status]).to eq(:fresh)
    end
  end
end
