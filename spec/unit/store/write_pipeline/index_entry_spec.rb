require "spec_helper"

# rubocop:disable RSpec/VerifiedDoubles
RSpec.describe "WritePipeline indexing" do
  let(:entry_index) { instance_double(Textus::Infra::Store::EntryIndex) }
  let(:audit_log) { instance_double(Textus::Infra::Store::AuditLog) }
  let(:call) { instance_double(Textus::Value::Call, role: "automation", correlation_id: "abc") }

  describe Textus::Protocol::StoreEngine::PutPipeline::Emit do
    it "records the written entry in the index" do
      ctx = double("ctx", key: "knowledge.a", mentry: double(schema: "runbook", lane: "knowledge", format: "markdown"), eff_content: nil,
                          eff_body: "hello", envelope: double(etag: "abc"), etag_before: nil)
      deps = double("deps", entry_index:, audit_log:, call:)
      allow(entry_index).to receive(:record)
      allow(audit_log).to receive(:append)
      allow(Textus::Protocol::StoreEngine::Pipeline).to receive(:emit_event)

      described_class.call(ctx, deps)

      expect(entry_index).to have_received(:record).with(
        key: "knowledge.a", lane: "knowledge", format: "markdown",
        schema: "runbook", content: "hello"
      )
    end

    it "indexes serialized content (not body) when the entry is content-based (json/yaml)" do
      ctx = double("ctx", key: "artifacts.b", mentry: double(schema: nil, lane: "artifacts", format: "json"), eff_content: { "x" => 1 },
                          eff_body: nil, envelope: double(etag: "def"), etag_before: nil)
      deps = double("deps", entry_index:, audit_log:, call:)
      allow(entry_index).to receive(:record)
      allow(audit_log).to receive(:append)
      allow(Textus::Protocol::StoreEngine::Pipeline).to receive(:emit_event)

      described_class.call(ctx, deps)

      expect(entry_index).to have_received(:record).with(
        key: "artifacts.b", lane: "artifacts", format: "json",
        schema: nil, content: { "x" => 1 }.to_json
      )
    end
  end

  describe Textus::Protocol::StoreEngine::DeletePipeline::DeindexEntry do
    it "removes the entry from the index" do
      ctx = double("ctx", key: "knowledge.a")
      deps = double("deps", entry_index:)
      allow(entry_index).to receive(:remove)

      described_class.call(ctx, deps)

      expect(entry_index).to have_received(:remove).with(key: "knowledge.a")
    end
  end

  describe Textus::Protocol::StoreEngine::MovePipeline::ReindexEntry do
    it "removes the old key and records the new key" do
      ctx = double("ctx", from_key: "knowledge.a", to_key: "knowledge.b", envelope: double(meta: nil, body: "hello", content: nil),
                          to_entry: double(schema: nil, lane: "knowledge", format: "markdown"))
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
