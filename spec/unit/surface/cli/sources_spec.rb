require "spec_helper"
require "tempfile"
require "stringio"
require "json"

RSpec.describe Textus::Surface::CLI::Sources do
  let(:spec) do
    Class.new do
      extend Textus::Contract::DSL

      verb :demo
      arg :doc, String, positional: true, source: :file
      arg :since, String, coerce: ->(s) { "T:#{s}" }
    end.contract
  end

  it "reads a :file-source arg's value from disk" do
    Tempfile.create("doc") do |f|
      f.write("hello")
      f.flush
      out = described_class.acquire(spec, { doc: f.path, since: "2h" })
      expect(out[:doc]).to eq("hello")
    end
  end

  it "applies a coerce callable to a raw value" do
    out = described_class.acquire(spec, { doc: "/dev/null", since: "2h" })
    expect(out[:since]).to eq("T:2h")
  end

  it "parses a cli_stdin :json envelope to a by-wire-name hash" do
    spec2 = Class.new do
      extend Textus::Contract::DSL

      verb :demo2
      cli_stdin :json
      arg :meta, Hash, wire_name: :_meta
      arg :body, String
    end.contract
    io = StringIO.new(JSON.dump("_meta" => { "x" => 1 }, "body" => "hi"))
    out = described_class.from_stdin(spec2, io)
    expect(out).to eq(meta: { "x" => 1 }, body: "hi")
  end
end
