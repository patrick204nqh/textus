# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Port::Store do
  let(:root) { File.join(Dir.mktmpdir, ".textus") }

  after { FileUtils.rm_rf(File.dirname(root)) }

  it "uses Layout.store_db as its path" do
    store = described_class.new(root: root)
    expect(store.path).to eq(Textus::Store::Geometry.new(root).store_db_path)
    store.close
  end

  it "opens a SQLite connection and creates the schema" do
    store = described_class.new(root: root)
    store.setup!

    tables = store.execute("SELECT name FROM sqlite_master WHERE type IN ('table', 'index')").map { |r| r["name"] }
    expect(tables).to include("entries", "entries_fts", "jobs", "idx_jobs_state", "idx_entries_lane")

    store.close
  end

  it "enables WAL mode" do
    store = described_class.new(root: root)
    store.setup!

    mode = store.query_value("PRAGMA journal_mode")
    expect(mode).to eq("wal")

    store.close
  end

  it "closes the database connection" do
    store = described_class.new(root: root)
    store.setup!
    store.close

    expect { store.execute("SELECT 1") }.to raise_error(ArgumentError)
  end
end
