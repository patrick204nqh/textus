require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Produced do
  def produced(source_raw)
    common = { raw: { "source" => source_raw }, key: "z.k", path: "z/k.json", lane: "z",
               schema: nil, owner: "agent:self", format: "json", publish_targets: [] }
    described_class.from_raw(common, { "source" => source_raw })
  end

  it "is intake for from: fetch" do
    e = produced("from" => "fetch", "handler" => "h")
    expect(e.intake?).to be(true)
    expect(e.derived?).to be(false)
    expect(e.handler).to eq("h")
  end

  it "is derived+projection for from: derive" do
    e = produced("from" => "derive", "select" => ["k.*"])
    expect(e.derived?).to be(true)
    expect(e.projection?).to be(true)
    expect(e.external?).to be(false)
  end

  it "is external for from: external" do
    e = produced("from" => "external", "command" => "make")
    expect(e.derived?).to be(false)
    expect(e.external?).to be(true)
    expect(e.projection?).to be(false)
  end

  it "registers under :produced" do
    expect(Textus::Manifest::Entry::REGISTRY[:produced]).to eq(described_class)
  end
end
