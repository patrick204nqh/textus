require "spec_helper"

RSpec.describe Textus::Contract do
  # A throwaway class that declares a contract, to test the DSL in isolation.
  let(:klass) do
    Class.new do
      extend Textus::Contract::DSL

      verb     :demo
      summary  "A demo verb."
      surfaces :cli, :mcp
      arg :key,  String, required: true, description: "the key"
      arg :flag, :boolean
      response { |v| { "echoed" => v } }
    end
  end

  it "exposes a frozen Spec" do
    expect(klass.contract?).to be(true)
    expect(klass.contract.verb).to eq(:demo)
    expect(klass.contract.summary).to eq("A demo verb.")
    expect(klass.contract.surfaces).to contain_exactly(:cli, :mcp)
    expect(klass.contract.mcp?).to be(true)
  end

  it "builds a JSON inputSchema from the args" do
    schema = klass.contract.input_schema
    expect(schema[:type]).to eq("object")
    expect(schema[:properties]["key"]).to eq("type" => "string", "description" => "the key")
    expect(schema[:properties]["flag"]).to eq("type" => "boolean")
    expect(schema[:required]).to eq(["key"])
  end

  it "carries a response shaper, defaulting to identity" do
    expect(klass.contract.response.call("x")).to eq("echoed" => "x")
    plain = Class.new do
      extend Textus::Contract::DSL

      verb :p
    end
    expect(plain.contract.response.call(42)).to eq(42)
  end

  it "reports a class without a contract" do
    expect(Class.new.respond_to?(:contract?)).to be(false)
  end

  it "raises if arg or verb is called after .contract has been read" do
    klass.contract # trigger memoization
    expect { klass.arg(:extra, String) }.to raise_error(RuntimeError, /contract already built/)
    expect { klass.verb(:other) }.to raise_error(RuntimeError, /contract already built/)
  end
end
