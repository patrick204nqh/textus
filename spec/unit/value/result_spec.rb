require "spec_helper"

RSpec.describe Textus::Value::Result do
  describe ".from_error" do
    it "wraps a Textus::Error instance as a failed Result carrying the original exception" do
      err = Textus::UsageError.new("bad input", hint: "fix your input")
      result = described_class.from_error(err)

      expect(result.success?).to be(false)
      expect(result.error[:code]).to eq("usage")
      expect(result.error[:message]).to eq("bad input")
    end
  end

  describe ".extract" do
    it "raises the original exception type for a Result built with .from_error" do
      err = Textus::UsageError.new("bad input")
      result = described_class.from_error(err)

      expect { described_class.extract(result) }.to raise_error(Textus::UsageError, "bad input")
    end

    it "still raises a generic ActionError for a Result built with .failure (unchanged behavior)" do
      result = described_class.failure(:something_wrong, "it broke")

      expect { described_class.extract(result) }.to raise_error(Textus::ActionError, "it broke")
    end

    it "preserves the raised exception's exit_code" do
      err = Textus::UsageError.new("bad input")
      result = described_class.from_error(err)

      begin
        described_class.extract(result)
      rescue Textus::UsageError => e
        expect(e.exit_code).to eq(2)
      end
    end
  end
end
