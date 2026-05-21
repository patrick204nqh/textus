require "spec_helper"
require "yaml"

RSpec.describe "Built-in hooks" do
  let(:reg) { Textus::Hooks::Registry.new }

  before { Textus.with_registry(reg) { Textus::Hooks::Builtin.register_all } }

  it "registers json, csv, markdown-links, ical-events, rss as :fetch hooks" do
    expect(reg.rpc_names(:fetch)).to contain_exactly(:json, :csv, :"markdown-links", :"ical-events", :rss)
  end

  it "json fetch hook parses JSON bytes from config['bytes']" do
    out = reg.rpc_callable(:fetch, :json).call(store: nil, config: { "bytes" => '{"a":1}' }, args: {})
    expect(out[:_meta]).to eq({})
    expect(YAML.safe_load(out[:body])).to eq({ "a" => 1 })
  end

  it "csv fetch hook parses CSV into array-of-hashes" do
    out = reg.rpc_callable(:fetch, :csv).call(store: nil, config: { "bytes" => "name,age\nalice,30\nbob,40\n" }, args: {})
    expect(YAML.safe_load(out[:body])).to eq(
      [{ "name" => "alice", "age" => "30" }, { "name" => "bob", "age" => "40" }],
    )
  end

  it "markdown-links fetch hook extracts text/href pairs" do
    md = "see [openai](https://openai.com) and [google](https://google.com)"
    out = reg.rpc_callable(:fetch, :"markdown-links").call(store: nil, config: { "bytes" => md }, args: {})
    expect(YAML.safe_load(out[:body])).to contain_exactly(
      { "text" => "openai", "href" => "https://openai.com" },
      { "text" => "google", "href" => "https://google.com" },
    )
  end

  it "ical-events fetch hook extracts VEVENT blocks" do
    ics = <<~ICS
      BEGIN:VEVENT
      SUMMARY:Hello
      DTSTART:20240101T000000Z
      END:VEVENT
      BEGIN:VEVENT
      SUMMARY:World
      LOCATION:Earth
      END:VEVENT
    ICS
    out = reg.rpc_callable(:fetch, :"ical-events").call(store: nil, config: { "bytes" => ics }, args: {})
    events = YAML.safe_load(out[:body])
    expect(events).to eq([
                           { "summary" => "Hello", "dtstart" => "20240101T000000Z" },
                           { "summary" => "World", "location" => "Earth" },
                         ])
  end

  it "rss fetch hook extracts item title/link/pubDate" do
    rss = <<~XML
      <rss><channel>
        <item><title>One</title><link>https://a</link><pubDate>now</pubDate></item>
        <item><title>Two</title><link>https://b</link><pubDate>later</pubDate></item>
      </channel></rss>
    XML
    out = reg.rpc_callable(:fetch, :rss).call(store: nil, config: { "bytes" => rss }, args: {})
    expect(YAML.safe_load(out[:body])).to eq([
                                               { "title" => "One", "link" => "https://a", "pubDate" => "now" },
                                               { "title" => "Two", "link" => "https://b", "pubDate" => "later" },
                                             ])
  end
end
