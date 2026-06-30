require "spec_helper"

RSpec.describe Textus::Event::Bus do
  let(:bus) { described_class.new }

  describe "typed events" do
    it "EntryWritten has expected fields" do
      ev = Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      )
      expect(ev.key).to eq("k")
      expect(ev.role).to eq("human")
    end
  end

  describe "#subscribe / #emit" do
    it "delivers the event to the matching subscriber" do
      received = []
      bus.subscribe(Textus::Event::EntryWritten) { |e| received << e }
      ev = Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      )
      bus.emit(ev)
      expect(received).to eq([ev])
    end

    it "does not deliver to subscribers for a different class" do
      received = []
      bus.subscribe(Textus::Event::EntryDeleted) { |e| received << e }
      bus.emit(Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      ))
      expect(received).to be_empty
    end

    it "two bus instances are completely isolated" do
      bus2 = described_class.new
      received = []
      bus.subscribe(Textus::Event::EntryWritten) { |e| received << e }
      bus2.emit(Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      ))
      expect(received).to be_empty
    end

    it "supports multiple subscribers for the same event class" do
      calls = []
      bus.subscribe(Textus::Event::EntryWritten) { |_e| calls << 1 }
      bus.subscribe(Textus::Event::EntryWritten) { |_e| calls << 2 }
      bus.emit(Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      ))
      expect(calls).to eq([1, 2])
    end
  end
end
