require "spec_helper"

RSpec.describe "textus init scaffolds zone kinds" do
  it "produces a manifest whose zones declare a known kind and that Schema accepts" do
    raw = YAML.safe_load(Textus::Init::DEFAULT_MANIFEST, aliases: false)
    kinds = raw["zones"].to_h { |z| [z["name"], z["kind"]] }
    expect(kinds).to eq(
      "identity" => "origin", "working" => "origin", "intake" => "quarantine",
      "review" => "queue", "output" => "derived"
    )
    expect { Textus::Manifest::Schema.validate!(raw) }.not_to raise_error
  end
end
