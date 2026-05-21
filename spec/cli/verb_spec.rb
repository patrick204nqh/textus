require "spec_helper"
require "stringio"

RSpec.describe Textus::CLI::Verb do
  let(:io) { { stdin: StringIO.new, stdout: StringIO.new, stderr: StringIO.new } }

  it "subclasses declare options and receive parsed values" do
    klass = Class.new(described_class) do
      def self.name = "DummyVerb"
      option :prefix, "--prefix=KEY"
      option :zone,   "--zone=Z"
      def call(_store)
        { "prefix" => prefix, "zone" => zone }
      end
    end

    v = klass.new(**io)
    v.parse(["--prefix=a.b", "--zone=working", "--format=json"])
    result = v.call(:fake_store)
    expect(result).to eq("prefix" => "a.b", "zone" => "working")
  end

  it "rejects --format values other than json" do
    klass = Class.new(described_class) do
      def self.name = "X"
      def call(_) = {}
    end
    v = klass.new(**io)
    expect { v.parse(["--format=yaml"]) }.to raise_error(Textus::UsageError, /only --format=json/)
  end

  it "defaults --format to json when omitted" do
    klass = Class.new(described_class) do
      def self.name = "Y"
      def call(_) = {}
    end
    v = klass.new(**io)
    expect { v.parse([]) }.not_to raise_error
  end

  it "exposes positional args after option parsing" do
    klass = Class.new(described_class) do
      def self.name = "Z"
      def call(_) = positional
    end
    v = klass.new(**io)
    v.parse(["alpha", "--format=json", "beta"])
    expect(v.positional).to eq(%w[alpha beta])
  end

  it "two subclasses have independent option registries" do
    a = Class.new(described_class) { option :alpha, "--alpha=A" }
    b = Class.new(described_class) { option :beta,  "--beta=B" }

    expect(a.options.map(&:first)).to eq([:alpha])
    expect(b.options.map(&:first)).to eq([:beta])
    expect(a.options).not_to be(b.options)
  end

  it "needs_store? defaults to true; subclasses may override to opt out" do
    store_free = Class.new(described_class) do
      def self.needs_store? = false
      def call(_) = 0
    end
    expect(described_class.needs_store?).to be(true)
    expect(store_free.needs_store?).to be(false)
  end
end
