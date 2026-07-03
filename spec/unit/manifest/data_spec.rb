require "spec_helper"

RSpec.describe Textus::Protocol::Manifest::Data do
  describe ".parse" do
    it "parses data: grouped by lane into flat entries with lane inferred" do
      data = described_class.parse(
        {
          "version" => "textus/4",
          "data" => {
            "knowledge" => [{ "key" => "knowledge.foo" }],
            "artifacts" => [{ "key" => "artifacts.bar" }],
          },
        },
        root: "/tmp/whatever",
      )
      expect(data.entries.map(&:key)).to contain_exactly("knowledge.foo", "artifacts.bar")
      expect(data.entries.find { |e| e.key == "knowledge.foo" }.lane).to eq("knowledge")
    end

    it "rejects a data: key that isn't one of the 5 fixed lane names" do
      expect do
        described_class.parse(
          { "version" => "textus/4", "data" => { "bogus" => [] } },
          root: "/tmp/whatever",
        )
      end.to raise_error(Textus::BadManifest, /unknown lane/)
    end

    it "rejects a manifest still declaring roles:" do
      expect do
        described_class.parse(
          { "version" => "textus/4", "roles" => [], "data" => {} },
          root: "/tmp/whatever",
        )
      end.to raise_error(Textus::BadManifest, /unknown top-level key 'roles'/)
    end

    it "rejects a manifest still declaring lanes:" do
      expect do
        described_class.parse(
          { "version" => "textus/4", "lanes" => [], "data" => {} },
          root: "/tmp/whatever",
        )
      end.to raise_error(Textus::BadManifest, /unknown top-level key 'lanes'/)
    end
  end
end
