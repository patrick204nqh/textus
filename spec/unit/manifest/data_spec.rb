require "spec_helper"

RSpec.describe Textus::Manifest::Data do
  describe ".parse" do
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
