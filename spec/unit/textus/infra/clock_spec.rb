require "spec_helper"

RSpec.describe Textus::Infra::Clock do
  subject(:clock) { described_class.new }

  describe "#now" do
    it "returns a Time" do
      expect(clock.now).to be_a(Time)
    end

    it "returns the current time" do
      frozen = Time.new(2026, 7, 3, 12, 0, 0, "+00:00")
      allow(Time).to receive(:now).and_return(frozen)
      expect(clock.now).to eq(frozen)
    end
  end
end
