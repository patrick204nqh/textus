# spec/unit/step/builtin_spec.rb
require "spec_helper"

RSpec.describe Textus::Step::Builtin do
  let(:registry) { Textus::Step::RegistryStore.new }

  before { described_class.register_all(registry) }

  it "registers all five built-in fetch steps" do
    expect(registry.names(:fetch)).to include(:json, :csv, :"markdown-links", :"ical-events", :rss)
  end

  it "json fetch parses JSON bytes to YAML body" do
    out = registry.invoke(:fetch, :json, caps: nil, config: { "bytes" => '{"a":1}' }, args: {})
    expect(YAML.safe_load(out[:body])).to eq({ "a" => 1 })
  end

  it "markdown-links fetch extracts links" do
    out = registry.invoke(:fetch, :"markdown-links", caps: nil, config: { "bytes" => "see [x](https://e.com)" }, args: {})
    expect(YAML.safe_load(out[:body])).to eq([{ "text" => "x", "href" => "https://e.com" }])
  end
end
