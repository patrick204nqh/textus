# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Infra::Database do
  let(:root) { File.join(Dir.mktmpdir, ".textus") }

  after { FileUtils.rm_rf(File.dirname(root)) }

  it "opens a SQLite connection and creates the schema" do
    db = described_class.new(root: root)
    db.setup!

    expect(db.connection.table_exists?(:events)).to be true
    expect(db.connection.table_exists?(:entries)).to be true
    expect(db.connection.table_exists?(:entries_fts)).to be true
    expect(db.connection.table_exists?(:link_edges)).to be true

    db.close
  end

  it "enables WAL mode" do
    db = described_class.new(root: root)
    db.setup!

    mode = db.connection.fetch("PRAGMA journal_mode").first[:journal_mode]
    expect(mode.downcase).to eq("wal")

    db.close
  end

  it "closes the database connection" do
    db = described_class.new(root: root)
    db.setup!
    db.close

    expect(db.connection).not_to be_nil
  end
end
