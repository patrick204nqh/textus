require "spec_helper"

RSpec.describe Textus::Contract::Binder do
  describe "validation is unconditional" do
    let(:spec) do
      Class.new do
        extend Textus::Contract::DSL

        verb :demo
        arg :key, String, required: true, positional: true
      end.contract
    end

    it "raises MissingArgs when a required arg is absent (no opt-out)" do
      expect { described_class.bind(spec, {}) }.to raise_error(Textus::Contract::MissingArgs)
    end

    it "does not accept a validate: keyword anymore" do
      expect(described_class.method(:bind).parameters.map(&:last)).not_to include(:validate)
    end
  end
end
