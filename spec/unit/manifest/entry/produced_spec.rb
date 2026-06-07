require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Produced do
  def produced(source_raw)
    common = { raw: { "source" => source_raw }, key: "z.k", path: "z/k.json", zone: "z",
               schema: nil, owner: "agent:self", format: "json", publish_targets: [] }
    described_class.from_raw(common, { "source" => source_raw })
  end

  it "is intake for from: handler" do
    e = produced("from" => "handler", "handler" => "h")
    expect(e.intake?).to be(true)
    expect(e.derived?).to be(false)
    expect(e.handler).to eq("h")
  end

  it "is derived+projection for from: project" do
    e = produced("from" => "project", "select" => ["k.*"])
    expect(e.derived?).to be(true)
    expect(e.projection?).to be(true)
    expect(e.external?).to be(false)
  end

  it "is derived+external for from: command" do
    e = produced("from" => "command", "command" => "make")
    expect(e.derived?).to be(true)
    expect(e.external?).to be(true)
    expect(e.projection?).to be(false)
  end

  it "registers under :produced" do
    expect(Textus::Manifest::Entry::REGISTRY[:produced]).to eq(described_class)
  end
end
