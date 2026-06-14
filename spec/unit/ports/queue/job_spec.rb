# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Ports::Queue::Job do
  describe "#id" do
    it "is content-addressed — same type + args produce the same id" do
      a = described_class.new(type: "materialize", args: { "key" => "k.x" })
      b = described_class.new(type: "materialize", args: { "key" => "k.x" })
      expect(a.id).to eq(b.id)
    end

    it "differs for different args" do
      a = described_class.new(type: "materialize", args: { "key" => "k.x" })
      b = described_class.new(type: "materialize", args: { "key" => "k.y" })
      expect(a.id).not_to eq(b.id)
    end
  end

  describe ".from_h / #to_h round-trip" do
    it "round-trips without data loss" do
      job = described_class.new(
        type: "sweep", args: { "scope" => {} },
        enqueued_by: "automation", attempts: 1, max_attempts: 3
      )
      expect(described_class.from_h(job.to_h).id).to eq(job.id)
      expect(described_class.from_h(job.to_h).attempts).to eq(1)
    end
  end
end
