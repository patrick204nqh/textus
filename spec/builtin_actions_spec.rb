require "spec_helper"
require "yaml"

RSpec.describe "Built-in actions" do
  let(:reg) { Textus::ExtensionRegistry.new }

  before { Textus.with_registry(reg) { Textus::BuiltinActions.register_all } }

  it "registers json, csv, markdown-links, ical-events, rss" do
    expect(reg.action_names).to contain_exactly(:json, :csv, :"markdown-links", :"ical-events", :rss)
  end

  it "json action parses JSON bytes from config['bytes']" do
    out = reg.action(:json).call(config: { "bytes" => '{"a":1}' }, store: nil, args: {})
    expect(out[:frontmatter]).to eq({})
    expect(YAML.safe_load(out[:body])).to eq({ "a" => 1 })
  end

  it "csv action parses CSV into array-of-hashes" do
    out = reg.action(:csv).call(config: { "bytes" => "name,age\nalice,30\nbob,40\n" }, store: nil, args: {})
    expect(YAML.safe_load(out[:body])).to eq(
      [{ "name" => "alice", "age" => "30" }, { "name" => "bob", "age" => "40" }],
    )
  end

  it "markdown-links action extracts text/href pairs" do
    md = "see [openai](https://openai.com) and [google](https://google.com)"
    out = reg.action(:"markdown-links").call(config: { "bytes" => md }, store: nil, args: {})
    expect(YAML.safe_load(out[:body])).to contain_exactly(
      { "text" => "openai", "href" => "https://openai.com" },
      { "text" => "google", "href" => "https://google.com" },
    )
  end

  it "ical-events action extracts VEVENT blocks" do
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
    out = reg.action(:"ical-events").call(config: { "bytes" => ics }, store: nil, args: {})
    events = YAML.safe_load(out[:body])
    expect(events).to eq([
                           { "summary" => "Hello", "dtstart" => "20240101T000000Z" },
                           { "summary" => "World", "location" => "Earth" },
                         ])
  end

  it "rss action extracts item title/link/pubDate" do
    rss = <<~XML
      <rss><channel>
        <item><title>One</title><link>https://a</link><pubDate>now</pubDate></item>
        <item><title>Two</title><link>https://b</link><pubDate>later</pubDate></item>
      </channel></rss>
    XML
    out = reg.action(:rss).call(config: { "bytes" => rss }, store: nil, args: {})
    expect(YAML.safe_load(out[:body])).to eq([
                                               { "title" => "One", "link" => "https://a", "pubDate" => "now" },
                                               { "title" => "Two", "link" => "https://b", "pubDate" => "later" },
                                             ])
  end
end
