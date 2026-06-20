# frozen_string_literal: true

require "textus/meta"

RSpec.describe Textus::Meta do
  describe ".inject_all" do
    it "mints a uid when none exists" do
      meta, = described_class.inject_all({}, {})
      expect(meta["uid"]).to be_a(String)
      expect(meta["uid"].length).to eq(16)
    end

    it "preserves an existing uid" do
      meta, = described_class.inject_all({ "uid" => "abc123" }, {})
      expect(meta["uid"]).to eq("abc123")
    end

    it "uses existing_meta uid when payload has none" do
      meta, = described_class.inject_all({}, {}, { "uid" => "stored-uid" })
      expect(meta["uid"]).to eq("stored-uid")
    end

    it "returns text entry unchanged (no metadata channel)" do
      meta, = described_class.inject_all({}, { body: "raw" }, {}, format: "text")
      expect(meta["uid"]).to be_nil
      expect(meta["sources"]).to be_nil
    end

    it "preserves sources from payload meta" do
      meta, = described_class.inject_all({ "sources" => ["raw.2026.06.20.url-foo"] }, {})
      expect(meta["sources"]).to eq(["raw.2026.06.20.url-foo"])
    end

    it "preserves sources from existing_meta when payload has none" do
      existing = { "sources" => ["raw.2026.06.20.url-foo"] }
      meta, = described_class.inject_all({}, {}, existing)
      expect(meta["sources"]).to eq(["raw.2026.06.20.url-foo"])
    end

    it "allows new sources to replace existing" do
      existing = { "sources" => ["raw.2026.06.20.url-old"] }
      payload = { "sources" => ["raw.2026.06.20.url-new"] }
      meta, = described_class.inject_all(payload, {}, existing)
      expect(meta["sources"]).to eq(["raw.2026.06.20.url-new"])
    end

    it "rejects non-array sources" do
      expect do
        described_class.inject_all({ "sources" => "not-an-array" }, {})
      end.to raise_error(Textus::BadContent, /sources must be an array/)
    end

    it "rejects non-string source elements" do
      expect do
        described_class.inject_all({ "sources" => [42] }, {})
      end.to raise_error(Textus::BadContent, /must be a string/)
    end

    it "rejects source with bad raw prefix" do
      expect do
        described_class.inject_all({ "sources" => ["knowledge.something"] }, {})
      end.to raise_error(Textus::BadContent, /must start with 'raw\.'/)
    end
  end
end
