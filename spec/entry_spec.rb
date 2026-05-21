require "spec_helper"

RSpec.describe Textus::Entry do
  describe "back-compat default surface" do
    it "Entry.parse defaults to markdown" do
      result = Textus::Entry.parse("---\ntitle: T\n---\nbody\n", path: "x.md")
      expect(result["_meta"]).to eq({ "title" => "T" })
      expect(result["body"]).to eq("body\n")
    end

    it "Entry.serialize defaults to markdown" do
      raw = Textus::Entry.serialize(meta: { "k" => "v" }, body: "b")
      expect(raw).to include("---\nk: v\n---\nb\n")
    end

    it ".for_format raises on unknown" do
      expect { Textus::Entry.for_format("xml") }.to raise_error(Textus::UsageError)
    end
  end
end
