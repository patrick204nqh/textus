require "spec_helper"

RSpec.describe "textus init scaffolds Setup-1 zone kinds (ADR 0033)" do
  it "declares the four Setup-1 zones with the right kinds and validates" do
    raw = YAML.safe_load(Textus::Init::DEFAULT_MANIFEST, aliases: false)
    kinds = raw["zones"].to_h { |z| [z["name"], z["kind"]] }
    expect(kinds).to eq(
      "knowledge" => "canon", "notebook" => "workspace",
      "proposals" => "queue", "artifacts" => "machine"
    )
    expect { Textus::Manifest::Schema.validate!(raw) }.not_to raise_error
  end

  it "gives agent a keep capability and human author" do
    raw = YAML.safe_load(Textus::Init::DEFAULT_MANIFEST, aliases: false)
    caps = raw["roles"].to_h { |r| [r["name"], r["can"]] }
    expect(caps["agent"]).to include("keep")
    expect(caps["human"]).to include("author")
  end
end
