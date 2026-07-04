require "spec_helper"
require "digest"

# Conformance fixture A from textus/4 §12: resolve and read.
RSpec.describe "textus/4 conformance — Fixture A: resolve and read" do
  include_context "textus/4 conformance fixture"

  describe "Fixture A — resolve and read" do
    it "returns the canonical envelope with a matching sha256 etag" do
      wire = store.with_role(Textus::Value::Role::DEFAULT).get(key: "knowledge.evidence.0001-topic")

      aggregate_failures do
        expect(wire["protocol"]).to eq("textus/4")
        expect(wire["key"]).to eq("knowledge.evidence.0001-topic")
        expect(wire["lane"]).to eq("knowledge")
        expect(File.absolute_path?(wire["path"])).to be true
        expect(wire["path"]).to end_with("knowledge/evidence/0001-topic.md")

        expect(wire["_meta"]).to eq("title" => "A topic")
        expect(wire["body"]).to include("Body content.")

        expected = "sha256:#{Digest::SHA256.hexdigest(File.binread(wire["path"]))}"
        expect(wire["etag"]).to eq(expected)
      end
    end
  end
end
