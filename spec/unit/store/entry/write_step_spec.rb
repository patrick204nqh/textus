require "spec_helper"

RSpec.describe Textus::Store::Entry::WriteStep do
  let(:key) { "knowledge.demo" }
  let(:mentry) { instance_double(Textus::Manifest::Entry::Leaf, format: :markdown, lane: "knowledge", schema: nil) }
  let(:payload) { Textus::Value::Payload.new(meta: { "title" => "Demo" }, body: "hello", content: nil) }

  describe "WriteContext" do
    it "holds inputs and all step outputs as nil by default" do
      ctx = described_class::WriteContext.new(
        key: key, mentry: mentry, payload: payload, if_etag: nil,
        path: nil, existing_env: nil, meta: nil, content: nil,
        bytes: nil, eff_meta: nil, eff_body: nil, eff_content: nil,
        etag_before: nil, envelope: nil
      )
      expect(ctx.key).to eq(key)
      expect(ctx.path).to be_nil
      expect(ctx.envelope).to be_nil
    end

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

  describe "DEFAULT_PUT" do
    it "is an array of modules with .call" do
      expect(described_class::DEFAULT_PUT).to all(respond_to(:call))
    end

    it "contains exactly the expected steps in order" do
      names = described_class::DEFAULT_PUT.map(&:name).map { |n| n.split("::").last }
      expect(names).to eq(%w[
                            ResolvePath ReadExisting InjectMeta Serialize
                            EnforceNameMatch ValidateSchema ValidateRaw
                            CheckEtag WriteBytes BuildEnvelope AppendAudit
                          ])
    end
  end
end
