require "spec_helper"

RSpec.describe Textus::Parsers do
  it "parses json into a hash" do
    expect(Textus::Parsers.parse("json", '{"a":1}')).to eq({ "a" => 1 })
  end

  it "parses csv into array-of-hashes" do
    out = Textus::Parsers.parse("csv", "name,age\nalice,30\nbob,40\n")
    expect(out).to eq([{ "name" => "alice", "age" => "30" }, { "name" => "bob", "age" => "40" }])
  end

  it "extracts markdown links" do
    md = "see [openai](https://openai.com) and [google](https://google.com)"
    out = Textus::Parsers.parse("markdown-links", md)
    expect(out).to contain_exactly(
      { "text" => "openai", "href" => "https://openai.com" },
      { "text" => "google", "href" => "https://google.com" },
    )
  end

  it "raises on unknown parser" do
    expect { Textus::Parsers.parse("nope", "") }.to raise_error(Textus::UsageError)
  end
end
