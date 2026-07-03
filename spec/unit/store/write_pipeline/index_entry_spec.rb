require "spec_helper"

# rubocop:disable RSpec/VerifiedDoubles
RSpec.describe "WritePipeline indexing" do
  let(:entry_index) { instance_double(Textus::Protocol::Index) }

  describe Textus::Infra::Store::WritePipeline::Put::IndexEntry do
    it "records the written entry in the index" do
      ctx = double("ctx", key: "knowledge.a", mentry: double(schema: "runbook", lane: "knowledge", format: "markdown"), eff_content: nil,
                          eff_body: "hello")
      deps = double("deps", entry_index:)
      allow(entry_index).to receive(:record)

      described_class.call(ctx, deps)

      expect(entry_index).to have_received(:record).with(
        key: "knowledge.a", lane: "knowledge", format: "markdown",
        schema: "runbook", content: "hello"
      )
    end

    it "indexes serialized content (not body) when the entry is content-based (json/yaml)" do
      ctx = double("ctx", key: "artifacts.b", mentry: double(schema: nil, lane: "artifacts", format: "json"), eff_content: { "x" => 1 },
                          eff_body: nil)
      deps = double("deps", entry_index:)
      allow(entry_index).to receive(:record)

      described_class.call(ctx, deps)

      expect(entry_index).to have_received(:record).with(
        key: "artifacts.b", lane: "artifacts", format: "json",
        schema: nil, content: { "x" => 1 }.to_json
      )
    end
  end

  describe Textus::Infra::Store::WritePipeline::Delete::DeindexEntry do
    it "removes the entry from the index" do
      ctx = double("ctx", key: "knowledge.a")
      deps = double("deps", entry_index:)
      allow(entry_index).to receive(:remove)

      described_class.call(ctx, deps)

      expect(entry_index).to have_received(:remove).with(key: "knowledge.a")
    end
  end

  describe Textus::Infra::Store::WritePipeline::Move::ReindexEntry do
    it "removes the old key and records the new key" do
      ctx = double("ctx", from_key: "knowledge.a", to_key: "knowledge.b", envelope: double(meta: nil, body: "hello", content: nil),
                          new_mentry: double(schema: nil, lane: "knowledge", format: "markdown"))
      deps = double("deps", entry_index:)
      allow(entry_index).to receive(:remove)
      allow(entry_index).to receive(:record)

      described_class.call(ctx, deps)

      expect(entry_index).to have_received(:remove).with(key: "knowledge.a")
      expect(entry_index).to have_received(:record).with(
        key: "knowledge.b", lane: "knowledge", format: "markdown",
        schema: nil, content: "hello"
      )
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles
