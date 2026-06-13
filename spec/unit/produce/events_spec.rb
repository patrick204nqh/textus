require "spec_helper"

RSpec.describe Textus::Produce::Events do
  def recording_events
    Class.new do
      attr_reader :published

      def initialize = @published = []

      def publish(event, **payload)
        @published << [event, payload]
        Textus::Step::FireReport.new(fired: [], errored: [], timed_out: [])
      end
    end.new
  end

  subject(:fe) { described_class.new(steps: bus, hook_context: ctx) }

  let(:bus) { recording_events }
  let(:ctx) { :stub_ctx }

  it "publishes :entry_fetch_started with the context, key and mode" do
    fe.started("intake.item")
    expect(bus.published).to eq([[:entry_fetch_started, { ctx: :stub_ctx, key: "intake.item", mode: :sync }]])
  end

  it "publishes :entry_fetch_failed with the error class and message" do
    fe.failed("intake.item", Textus::UsageError.new("boom"))
    event, payload = bus.published.first
    expect(event).to eq(:entry_fetch_failed)
    expect(payload).to include(ctx: :stub_ctx, key: "intake.item",
                               error_class: "Textus::UsageError", error_message: "boom")
  end

  it "publishes :entry_fetched only when the change is not :unchanged" do
    env = instance_double(Textus::Envelope)
    fe.fetched("intake.item", env, :unchanged)
    expect(bus.published).to be_empty

    fe.fetched("intake.item", env, :created)
    event, payload = bus.published.first
    expect(event).to eq(:entry_fetched)
    expect(payload).to include(ctx: :stub_ctx, key: "intake.item", envelope: env, change: :created)
  end
end
