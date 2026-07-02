# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Port::Store do
  let(:root) { File.join(Dir.mktmpdir, ".textus") }

  after { FileUtils.rm_rf(File.dirname(root)) }

  it "uses Layout.store_db as its path" do
    geometry = Textus::Store::Layout.new(root)
    store = described_class.new(root: root)
    expect(store.path).to eq(geometry.store_db_path)
    store.close
  end

  it "opens a SQLite connection and creates the schema" do
    store = described_class.new(root: root)
    store.setup!

    expect(store.db.table_exists?(:events)).to be true
    expect(store.db.table_exists?(:entries)).to be true
    expect(store.db.table_exists?(:entries_fts)).to be true
    expect(store.db.table_exists?(:link_edges)).to be true
    expect(store.db.table_exists?(:audit_events)).to be true

    store.close
  end

  it "enables WAL mode" do
    store = described_class.new(root: root)
    store.setup!

    mode = store.db.fetch("PRAGMA journal_mode").first[:journal_mode]
    expect(mode.downcase).to eq("wal")

    store.close
  end

  it "closes the database connection" do
    store = described_class.new(root: root)
    store.setup!
    store.close

    expect(store.db).to_not be_nil
  end
end
