require "spec_helper"

RSpec.describe "Entry strategy: inject_uid" do
  describe "Markdown (via Meta.inject_all)" do
    it "adds uid when none exists" do
      meta, = Textus::Store::Envelope::Meta.inject_all({}, {}, { "uid" => "abc123def4561234" })
      expect(meta["uid"]).to eq("abc123def4561234")
    end

    it "preserves existing uid in meta" do
      meta, = Textus::Store::Envelope::Meta.inject_all({ "uid" => "existing" }, {}, { "uid" => "newone" })
      expect(meta["uid"]).to eq("existing")
    end

    it "mints a fresh uid when existing_meta has no uid and meta has no uid" do
      meta, = Textus::Store::Envelope::Meta.inject_all({}, {}, {})
      expect(meta["uid"]).to match(/\A[0-9a-f]{16}\z/)
    end
  end

  describe "Text (no metadata channel)" do
    it "is a no-op (text has no _meta home for uid)" do
      meta, content = Textus::Store::Envelope::Meta.inject_all({}, { body: "body" }, { "uid" => "uid123" }, format: "text")
      expect(meta["uid"]).to be_nil
      expect(content).to eq(body: "body")
    end
  end
end
