require "spec_helper"

RSpec.describe Textus::Manifest::Policy::Source do
  it "accepts from: external" do
    src = described_class.new("from" => "external", "command" => "make build", "sources" => ["lib/"])
    expect(src.external?).to be(true)
    expect(src.command).to eq("make build")
  end

  it "rejects from: fetch with BadManifest" do
    expect { described_class.new("from" => "fetch", "handler" => "my_step") }
      .to raise_error(Textus::BadManifest, /from: fetch.*removed/)
  end

  it "rejects from: derive with BadManifest" do
    expect { described_class.new("from" => "derive", "select" => ["knowledge.x"]) }
      .to raise_error(Textus::BadManifest, /from: derive.*removed/)
  end
end
