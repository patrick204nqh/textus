require "spec_helper"

RSpec.describe Textus::Builder::Renderer::Json do
  def make_mentry(provenance: true, template: nil, transform: nil)
    instance_double(
      Textus::Manifest::Entry::Derived,
      key: "output.config",
      format: "json",
      template: template,
      provenance: provenance,
      source: Textus::Manifest::Entry::Derived::Projection.new(
        select: ["working.*"], pluck: nil, sort_by: nil, transform: transform,
      ),
    )
  end

  let(:renderer) { described_class.new(template_loader: ->(_) { raise "not used" }) }

  describe "provenance: true (default)" do
    it "includes _meta in the built JSON" do
      mentry = make_mentry(provenance: true)
      data = { "entries" => [{ "key" => "working.a" }] }
      bytes = renderer.call(mentry: mentry, data: data)
      parsed = JSON.parse(bytes)
      expect(parsed).to have_key("_meta")
    end
  end

  describe "provenance: false" do
    it "omits _meta from the built JSON" do
      mentry = make_mentry(provenance: false)
      data = { "entries" => [{ "key" => "working.a" }] }
      bytes = renderer.call(mentry: mentry, data: data)
      parsed = JSON.parse(bytes)
      expect(parsed).not_to have_key("_meta")
    end

    it "preserves the rest of the content unchanged" do
      mentry = make_mentry(provenance: false, transform: true)
      data = { "mcpServers" => { "textus" => { "command" => "textus" } } }
      bytes = renderer.call(mentry: mentry, data: data)
      parsed = JSON.parse(bytes)
      expect(parsed["mcpServers"]).to eq({ "textus" => { "command" => "textus" } })
      expect(parsed).not_to have_key("_meta")
    end
  end
end
