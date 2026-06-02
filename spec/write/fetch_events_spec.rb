require "spec_helper"

RSpec.describe Textus::Write::FetchEvents do
  def recording_events
    Class.new do
      attr_reader :published
      def initialize = @published = []
      def publish(event, **payload)
        @published << [event, payload]
        Textus::Hooks::FireReport.new(fired: [], errored: [], timed_out: [])
      end
    end.new
  end

  let(:bus) { recording_events }
  let(:ctx) { :stub_ctx }
  subject(:fe) { described_class.new(events: bus, hook_context: ctx) }

  it "publishes :fetch_started with the context, key and mode" do
    fe.started("intake.item")
    expect(bus.published).to eq([[:fetch_started, { ctx: :stub_ctx, key: "intake.item", mode: :sync }]])
  end

  it "publishes :fetch_failed with the error class and message" do
    fe.failed("intake.item", Textus::UsageError.new("boom"))
    event, payload = bus.published.first
    expect(event).to eq(:fetch_failed)
    expect(payload).to include(ctx: :stub_ctx, key: "intake.item",
                               error_class: "Textus::UsageError", error_message: "boom")
  end

  it "publishes :entry_fetched only when the change is not :unchanged" do
    env = double("envelope")
    fe.fetched("intake.item", env, :unchanged)
    expect(bus.published).to be_empty

    fe.fetched("intake.item", env, :created)
    event, payload = bus.published.first
    expect(event).to eq(:entry_fetched)
    expect(payload).to include(ctx: :stub_ctx, key: "intake.item", envelope: env, change: :created)
  end

  it "publishes :fetch_backgrounded with started_at and budget_ms" do
    fe.backgrounded("intake.item", started_at: "2026-06-02T00:00:00Z", budget_ms: 1500)
    event, payload = bus.published.first
    expect(event).to eq(:fetch_backgrounded)
    expect(payload).to include(ctx: :stub_ctx, key: "intake.item",
                               started_at: "2026-06-02T00:00:00Z", budget_ms: 1500)
  end
end
