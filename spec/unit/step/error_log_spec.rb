require "spec_helper"

RSpec.describe Textus::Step::ErrorLog do
  it "stores errors and returns them in insertion order via since(seq)" do
    log = described_class.new(capacity: 8)
    log.record(seq: 1, event: :entry_written, hook: :h1, key: "a", error_class: "Foo", error_message: "boom")
    log.record(seq: 2, event: :entry_written, hook: :h2, key: "b", error_class: "Bar", error_message: "kaboom")
    rows = log.since(0)
    expect(rows.map { |r| r[:hook] }).to eq(%i[h1 h2])
  end

  it "filters strictly greater than seq" do
    log = described_class.new(capacity: 8)
    log.record(seq: 1, event: :x, hook: :h1, key: nil, error_class: "E", error_message: "m")
    log.record(seq: 5, event: :x, hook: :h2, key: nil, error_class: "E", error_message: "m")
    expect(log.since(1).map { |r| r[:seq] }).to eq([5])
  end

  it "evicts oldest entries when capacity is exceeded" do
    log = described_class.new(capacity: 2)
    log.record(seq: 1, event: :x, hook: :h1, key: nil, error_class: "E", error_message: "m")
    log.record(seq: 2, event: :x, hook: :h2, key: nil, error_class: "E", error_message: "m")
    log.record(seq: 3, event: :x, hook: :h3, key: nil, error_class: "E", error_message: "m")
    expect(log.since(0).map { |r| r[:seq] }).to eq([2, 3])
  end
end
