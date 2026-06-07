require "spec_helper"

RSpec.describe "Built-in hooks" do
  let(:events) { Textus::Hooks::EventBus.new }
  let(:rpc)    { Textus::Hooks::RpcRegistry.new }

  before { Textus::Hooks::Builtin.register_all(events: events, rpc: rpc) }

  it "registers json, csv, markdown-links, ical-events, rss as :resolve_handler hooks" do
    expect(rpc.names(:resolve_handler)).to contain_exactly(:json, :csv, :"markdown-links", :"ical-events", :rss)
  end

  it "json resolve_handler hook parses JSON bytes from config['bytes']" do
    out = rpc.invoke(:resolve_handler, :json, caps: nil, config: { "bytes" => '{"a":1}' }, args: {})
    expect(out[:_meta]).to eq({})
    expect(YAML.safe_load(out[:body])).to eq({ "a" => 1 })
  end

  it "csv resolve_handler hook parses CSV into array-of-hashes" do
    out = rpc.invoke(:resolve_handler, :csv, caps: nil, config: { "bytes" => "name,age\nalice,30\nbob,40\n" }, args: {})
    expect(YAML.safe_load(out[:body])).to eq(
      [{ "name" => "alice", "age" => "30" }, { "name" => "bob", "age" => "40" }],
    )
  end

  it "markdown-links resolve_handler hook extracts text/href pairs" do
    md = "see [openai](https://openai.com) and [google](https://google.com)"
    out = rpc.invoke(:resolve_handler, :"markdown-links", caps: nil, config: { "bytes" => md }, args: {})
    expect(YAML.safe_load(out[:body])).to contain_exactly(
      { "text" => "openai", "href" => "https://openai.com" },
      { "text" => "google", "href" => "https://google.com" },
    )
  end

  it "ical-events resolve_handler hook extracts VEVENT blocks" do
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
    out = rpc.invoke(:resolve_handler, :"ical-events", caps: nil, config: { "bytes" => ics }, args: {})
    events_list = YAML.safe_load(out[:body])
    expect(events_list).to eq([
                                { "summary" => "Hello", "dtstart" => "20240101T000000Z" },
                                { "summary" => "World", "location" => "Earth" },
                              ])
  end

  it "rss resolve_handler hook extracts item title/link/pubDate" do
    rss = <<~XML
      <rss><channel>
        <item><title>One</title><link>https://a</link><pubDate>now</pubDate></item>
        <item><title>Two</title><link>https://b</link><pubDate>later</pubDate></item>
      </channel></rss>
    XML
    out = rpc.invoke(:resolve_handler, :rss, caps: nil, config: { "bytes" => rss }, args: {})
    expect(YAML.safe_load(out[:body])).to eq([
                                               { "title" => "One", "link" => "https://a", "pubDate" => "now" },
                                               { "title" => "Two", "link" => "https://b", "pubDate" => "later" },
                                             ])
  end
end
