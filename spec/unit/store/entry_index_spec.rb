require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Infra::Store::EntryIndex do
  subject(:index) { described_class.new(database.connection) }

  let(:root) { Dir.mktmpdir }
  let(:layout) { Textus::Protocol::Layout.new(root) }
  let(:database) { Textus::Infra::Database.new(layout:).setup! }

  after { FileUtils.remove_entry(root) }

  describe "#record and #search" do
    it "finds a recorded entry by full-text content match" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "hello world")

      rows = index.search(query: "hello", schema: nil, lane: nil, under: nil)

      expect(rows.map { |r| r[:key] }).to eq(["knowledge.a"])
    end

    it "does not error and returns no rows for a non-matching query" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "hello world")

      rows = index.search(query: "nonexistent-term", schema: nil, lane: nil, under: nil)

      expect(rows).to eq([])
    end

    it "filters by schema" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: "runbook", content: "x")
      index.record(key: "knowledge.b", lane: "knowledge", format: "markdown", schema: "adr", content: "x")

      rows = index.search(query: nil, schema: "runbook", lane: nil, under: nil)

      expect(rows.map { |r| r[:key] }).to eq(["knowledge.a"])
    end

    it "filters by lane and prefix" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "x")
      index.record(key: "artifacts.b", lane: "artifacts", format: "json", schema: nil, content: "x")

      rows = index.search(query: nil, schema: nil, lane: "knowledge", under: "knowledge.")

      expect(rows.map { |r| r[:key] }).to eq(["knowledge.a"])
    end

    it "upserts on repeated record calls for the same key" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "first version")
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "second version")

      rows = index.search(query: "second", schema: nil, lane: nil, under: nil)
      expect(rows.map { |r| r[:key] }).to eq(["knowledge.a"])

      stale = index.search(query: "first", schema: nil, lane: nil, under: nil)
      expect(stale).to eq([])
    end
  end

  describe "#remove" do
    it "removes the entry from the index" do
      index.record(key: "knowledge.a", lane: "knowledge", format: "markdown", schema: nil, content: "hello")
      index.remove(key: "knowledge.a")

      rows = index.search(query: "hello", schema: nil, lane: nil, under: nil)
      expect(rows).to eq([])
    end
  end
end
