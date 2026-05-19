require "spec_helper"
require "fileutils"
require "tmpdir"

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

  it "auto-loads parsers from .textus/parsers/<name>.rb" do
    tmp = Dir.mktmpdir
    root = File.join(tmp, ".textus")
    FileUtils.mkdir_p(File.join(root, "parsers"))
    File.write(File.join(root, "parsers/uppercase.rb"), <<~RUBY)
      Textus::Parsers.register("uppercase", ->(content) { content.upcase })
    RUBY
    FileUtils.mkdir_p(File.join(root, "zones"))
    File.write(File.join(root, "manifest.yaml"),
               "version: textus/1\nentries: []\n")
    Textus::Store.new(root)
    expect(Textus::Parsers.parse("uppercase", "hi")).to eq("HI")
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end

  it "enforces a 2s timeout on parser callables" do
    Textus::Parsers.register("slow", ->(_c) { sleep 5 })
    expect {
      Textus::Parsers.parse("slow", "hi")
    }.to raise_error(Textus::UsageError, /2s timeout/)
  end
end
