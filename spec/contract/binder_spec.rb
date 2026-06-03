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

  describe ".inputs_from_wire" do
    let(:spec) do
      Class.new do
        extend Textus::Contract::DSL

        verb :demo
        arg :key,  String, positional: true
        arg :meta, Hash, wire_name: :_meta
      end.contract
    end

    it "maps wire-named JSON keys to arg names, dropping absentees" do
      raw = { "key" => "k", "_meta" => { "a" => 1 } }
      expect(described_class.inputs_from_wire(spec, raw)).to eq(key: "k", meta: { "a" => 1 })
    end

    it "ignores keys not declared on the contract" do
      expect(described_class.inputs_from_wire(spec, { "key" => "k", "junk" => 9 })).to eq(key: "k")
    end
  end
end
