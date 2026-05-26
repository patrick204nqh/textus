require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators do
  describe ".run_all" do
    it "returns nil when no validators raise" do
      entry = Object.new
      stub_const("Textus::Manifest::Entry::Validators::REGISTERED", [])
      expect(described_class.run_all(entry)).to be_nil
    end

    it "calls each REGISTERED validator with the entry" do
      entry = Object.new
      v1 = Class.new { def self.call(_); end }
      v2 = Class.new { def self.call(_); end }
      allow(v1).to receive(:call)
      allow(v2).to receive(:call)
      stub_const("Textus::Manifest::Entry::Validators::REGISTERED", [v1, v2])

      described_class.run_all(entry)

      expect(v1).to have_received(:call).with(entry)
      expect(v2).to have_received(:call).with(entry)
    end

    it "stops on the first raise and propagates" do
      entry = Object.new
      v1 = Class.new { def self.call(_); end }
      v2 = Class.new do
        def self.call(_)
          raise Textus::UsageError.new("boom")
        end
      end
      v3 = Class.new { def self.call(_); end }
      allow(v1).to receive(:call)
      allow(v3).to receive(:call)
      stub_const("Textus::Manifest::Entry::Validators::REGISTERED", [v1, v2, v3])

      expect { described_class.run_all(entry) }.to raise_error(Textus::UsageError, "boom")
      expect(v3).not_to have_received(:call)
    end
  end
end
