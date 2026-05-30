require "spec_helper"

RSpec.describe Textus::Manifest::Rules do
  it "parses a guard map of transition => predicate specs" do
    rules = described_class.parse([
                                    { "match" => "working.**",
                                      "guard" => { "accept" => ["author_signed", "schema_valid", { "fresh_within" => "1h" }] } },
                                  ])
    set = rules.for("working.notes.x")
    expect(set.guard).to eq({ "accept" => ["author_signed", "schema_valid", { "fresh_within" => "1h" }] })
  end

  it "returns nil guard when no block matches" do
    expect(described_class.parse([]).for("working.x").guard).to be_nil
  end

  it "rejects a non-Hash guard:" do
    expect { described_class.parse([{ "match" => "working.**", "guard" => ["author_signed"] }]) }
      .to raise_error(Textus::BadManifest, /guard: must be a map/)
  end
end
