# spec/conformance/steps/builtin_spec.rb
require "spec_helper"

RSpec.describe "Built-in steps" do
  let(:registry) { Textus::Step::RegistryStore.new }

  before { Textus::Step::Builtin.register_all(registry) }

  it "registers json, csv, markdown-links, ical-events, rss as :fetch steps" do
    expect(registry.names(:fetch)).to contain_exactly(:json, :csv, :"markdown-links", :"ical-events", :rss)
  end

  it "json fetch step parses JSON bytes from config['bytes']" do
    out = registry.invoke(:fetch, :json, caps: nil, config: { "bytes" => '{"a":1}' }, args: {})
    expect(out).to be_a(Hash)
    expect(YAML.safe_load(out[:body])).to eq({ "a" => 1 })
  end

  it "csv fetch step parses CSV into array-of-hashes" do
    out = registry.invoke(:fetch, :csv, caps: nil, config: { "bytes" => "name,age\nalice,30\nbob,40\n" }, args: {})
    expect(YAML.safe_load(out[:body])).to eq(
      [{ "name" => "alice", "age" => "30" }, { "name" => "bob", "age" => "40" }],
    )
  end

  it "markdown-links fetch step extracts text/href pairs" do
    md = "see [openai](https://openai.com) and [google](https://google.com)"
    out = registry.invoke(:fetch, :"markdown-links", caps: nil, config: { "bytes" => md }, args: {})
    expect(YAML.safe_load(out[:body])).to contain_exactly(
      { "text" => "openai", "href" => "https://openai.com" },
      { "text" => "google", "href" => "https://google.com" },
    )
  end

  it "ical-events fetch step extracts VEVENT blocks" do
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
    out = registry.invoke(:fetch, :"ical-events", caps: nil, config: { "bytes" => ics }, args: {})
    events_list = YAML.safe_load(out[:body])
    expect(events_list).to eq([
                                { "summary" => "Hello", "dtstart" => "20240101T000000Z" },
                                { "summary" => "World", "location" => "Earth" },
                              ])
  end

  it "rss fetch step extracts item title/link/pubDate" do
    rss = <<~XML
      <rss><channel>
        <item><title>One</title><link>https://a</link><pubDate>now</pubDate></item>
        <item><title>Two</title><link>https://b</link><pubDate>later</pubDate></item>
      </channel></rss>
    XML
    out = registry.invoke(:fetch, :rss, caps: nil, config: { "bytes" => rss }, args: {})
    expect(YAML.safe_load(out[:body])).to eq([
                                               { "title" => "One", "link" => "https://a", "pubDate" => "now" },
                                               { "title" => "Two", "link" => "https://b", "pubDate" => "later" },
                                             ])
  end
end
