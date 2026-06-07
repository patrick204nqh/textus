require "spec_helper"

RSpec.describe Textus::Produce::Acquire::Serializer::Json do
  def make_mentry(transform: nil)
    instance_double(
      Textus::Manifest::Entry::Produced,
      key: "output.config",
      format: "json",
      derived?: true,
      projection?: true,
      source: Textus::Domain::Policy::Source.new(
        "from" => "project",
        "select" => ["working.a"],
        "transform" => transform,
      ),
    )
  end

  let(:renderer) { described_class.new }

  it "serializes projection data and always stamps _meta into the stored artifact (ADR 0094)" do
    mentry = make_mentry
    data = { "entries" => [{ "key" => "working.a" }] }
    parsed = JSON.parse(renderer.call(mentry: mentry, data: data))
    expect(parsed).to have_key("_meta")
    expect(parsed["entries"]).to eq([{ "key" => "working.a" }])
  end

  it "preserves transformed content shape (no entries wrapper) alongside _meta" do
    mentry = make_mentry(transform: true)
    data = { "mcpServers" => { "textus" => { "command" => "textus" } } }
    parsed = JSON.parse(renderer.call(mentry: mentry, data: data))
    expect(parsed["mcpServers"]).to eq({ "textus" => { "command" => "textus" } })
    expect(parsed).to have_key("_meta")
  end
end
