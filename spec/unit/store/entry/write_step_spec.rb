require "spec_helper"

RSpec.describe Textus::Store::Entry::WriteStep do
  let(:key) { "knowledge.demo" }
  let(:mentry) { instance_double(Textus::Manifest::Entry::Leaf, format: :markdown, lane: "knowledge", schema: nil) }
  let(:payload) { Textus::Value::Payload.new(meta: { "title" => "Demo" }, body: "hello", content: nil) }

  describe "WriteContext" do
    it "supports immutable update via #with" do
      ctx = described_class::WriteContext.new(
        key: key, mentry: mentry, payload: payload, if_etag: nil,
        path: nil, existing_env: nil, meta: nil, content: nil,
        bytes: nil, eff_meta: nil, eff_body: nil, eff_content: nil,
        etag_before: nil, envelope: nil
      )
      updated = ctx.with(path: "/tmp/demo.md")
      expect(updated.path).to eq("/tmp/demo.md")
      expect(ctx.path).to be_nil
    end
  end

  describe "DeleteContext" do
    it "supports immutable update via #with" do
      ctx = described_class::DeleteContext.new(
        key: "knowledge.demo", mentry: nil, if_etag: nil,
        path: nil, etag_before: nil
      )
      expect(ctx.with(path: "/tmp/demo.md").path).to eq("/tmp/demo.md")
      expect(ctx.path).to be_nil
    end
  end

  describe "MoveContext" do
    it "supports immutable update via #with" do
      ctx = described_class::MoveContext.new(
        from_key: "knowledge.alpha", to_key: "knowledge.beta",
        new_mentry: nil, if_etag: nil,
        from_path: nil, to_path: nil,
        etag_before: nil, etag_after: nil, envelope: nil
      )
      updated = ctx.with(from_path: "/tmp/alpha.md")
      expect(updated.from_path).to eq("/tmp/alpha.md")
      expect(ctx.from_path).to be_nil
    end
  end
end
