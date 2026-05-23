require "spec_helper"

RSpec.describe Textus::Schema do
  describe "#unowned_fields" do
    it "returns field names whose spec lacks 'maintained_by'" do
      schema = described_class.new(
        "name" => "note",
        "fields" => {
          "title" => { "type" => "string", "maintained_by" => "human" },
          "summary" => { "type" => "string" },
          "tags" => { "type" => "array" },
        },
      )
      expect(schema.unowned_fields).to contain_exactly("summary", "tags")
    end

    it "returns empty array when every field is owned" do
      schema = described_class.new(
        "name" => "note",
        "fields" => {
          "title" => { "type" => "string", "maintained_by" => "human" },
        },
      )
      expect(schema.unowned_fields).to eq([])
    end

    it "ignores non-Hash field specs (vendor extensions)" do
      schema = described_class.new(
        "name" => "note",
        "fields" => {
          "shorthand" => "string",
          "tags" => { "type" => "array" },
        },
      )
      expect(schema.unowned_fields).to contain_exactly("tags")
    end
  end
end
