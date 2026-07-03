require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Protocol::Index do
  subject(:index) { described_class.new(database) }

  let(:root) { Dir.mktmpdir }
  let(:database) { Textus::Port::Storage::Database.new(root: root).setup! }

  after { FileUtils.remove_entry(root) }

  describe "#record and #search" do
    it "finds a recorded entry by full-text content match" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "hello world")

      rows = index.search(query: "hello", schema: nil, lane: nil, prefix: nil)

      expect(rows.map { |r| r["key"] }).to eq(["knowledge.a"])
    end

    it "does not error and returns no rows for a non-matching query" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "hello world")

      rows = index.search(query: "nonexistent-term", schema: nil, lane: nil, prefix: nil)

      expect(rows).to eq([])
    end

    it "filters by schema" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: "runbook", content: "x")
      index.record(key: "knowledge.b", lane: "knowledge", format: "markdown", schema: "adr", content: "x")

      rows = index.search(query: nil, schema: "runbook", lane: nil, prefix: nil)

      expect(rows.map { |r| r["key"] }).to eq(["knowledge.a"])
    end

    it "filters by lane and prefix" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "x")
      index.record(key: "artifacts.b", lane: "artifacts", format: "json", schema: nil, content: "x")

      rows = index.search(query: nil, schema: nil, lane: "knowledge", prefix: "knowledge.")

      expect(rows.map { |r| r["key"] }).to eq(["knowledge.a"])
    end

    it "upserts on repeated record calls for the same key instead of ignoring the update" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "first version")
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "second version")

      rows = index.search(query: "second", schema: nil, lane: nil, prefix: nil)
      expect(rows.map { |r| r["key"] }).to eq(["knowledge.a"])

      stale = index.search(query: "first", schema: nil, lane: nil, prefix: nil)
      expect(stale).to eq([])
    end
  end

  describe "#remove" do
    it "removes the entry from the index" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "hello")
      index.remove(key: "knowledge.a")

      rows = index.search(query: "hello", schema: nil, lane: nil, prefix: nil)
      expect(rows).to eq([])
    end
  end
end
