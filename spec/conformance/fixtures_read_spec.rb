require "spec_helper"
require "digest"

# Conformance fixture A from textus/4 §12: resolve and read.
RSpec.describe "textus/4 conformance — Fixture A: resolve and read" do
  include_context "textus/4 conformance fixture"

  describe "Fixture A — resolve and read" do
    it "returns the canonical envelope with a matching sha256 etag" do
      env = store.with_role(Textus::Value::Role::DEFAULT).get(key: "knowledge.evidence.0001-topic")

      aggregate_failures do
        expect(env.protocol).to eq("textus/4")
        expect(env.key).to eq("knowledge.evidence.0001-topic")
        expect(env.lane).to eq("knowledge")
        expect(File.absolute_path?(env.path)).to be true
        expect(env.path).to end_with("knowledge/evidence/0001-topic.md")

        expect(env.meta).to eq("title" => "A topic")
        expect(env.body).to include("Body content.")

        expected = "sha256:#{Digest::SHA256.hexdigest(File.binread(env.path))}"
        expect(env.etag).to eq(expected)
      end
    end
  end
end
