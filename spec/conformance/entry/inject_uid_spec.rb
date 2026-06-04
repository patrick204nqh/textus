require "spec_helper"

RSpec.describe "Entry strategy: inject_uid" do
  describe "Markdown" do
    it "adds uid when none exists" do
      meta, content = Textus::Entry::Markdown.inject_uid({}, nil, "abc123def4561234")
      expect(meta["uid"]).to eq("abc123def4561234")
      expect(content).to be_nil
    end

    it "preserves existing uid in meta" do
      meta, = Textus::Entry::Markdown.inject_uid({ "uid" => "existing" }, nil, "newone")
      expect(meta["uid"]).to eq("existing")
    end

    it "mints a fresh uid when existing_uid is nil and meta has no uid" do
      meta, = Textus::Entry::Markdown.inject_uid({}, nil, nil)
      expect(meta["uid"]).to match(/\A[0-9a-f]{16}\z/)
    end
  end

  describe "Text" do
    it "is a no-op (text has no _meta home for uid)" do
      meta, content = Textus::Entry::Text.inject_uid(nil, "body", "uid123")
      expect(meta).to be_nil
      expect(content).to eq("body")
    end
  end
end
