require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Infra::Database do
  subject(:db) { described_class.new(layout:) }

  let(:tmpdir) { Dir.mktmpdir }
  let(:layout) { Textus::Protocol::Layout.new(tmpdir) }

  after do
    begin
      db.close
    rescue StandardError
      nil
    end
    FileUtils.rm_rf(tmpdir)
  end

  describe "#setup!" do
    it "creates the database file" do
      db.setup!
      expect(File).to exist(layout.db_path)
    end

    it "creates workflow_events table" do
      db.setup!
      expect(db.connection.table_exists?(:workflow_events)).to be true
    end

    it "creates entries table" do
      db.setup!
      expect(db.connection.table_exists?(:entries)).to be true
    end

    it "creates link_edges table" do
      db.setup!
      expect(db.connection.table_exists?(:link_edges)).to be true
    end

    it "creates entries_fts virtual table" do
      db.setup!
      expect(db.connection.table_exists?(:entries_fts)).to be true
    end

    it "is idempotent (safe to call twice)" do
      db.setup!
      expect { db.setup! }.not_to raise_error
    end
  end

  describe "#connection" do
    it "returns a Sequel database" do
      db.setup!
      expect(db.connection).to be_a(Sequel::SQLite::Database)
    end
  end

  describe "#transaction" do
    it "commits changes" do
      db.setup!
      db.transaction do
        db.connection[:workflow_events].insert(
          event_type: "test", workflow_type: "test",
          key: "test.key", lane: "raw"
        )
      end
      expect(db.connection[:workflow_events].count).to eq(1)
    end

    it "rolls back on error" do
      db.setup!
      expect do
        db.transaction do
          db.connection[:workflow_events].insert(
            event_type: "test", workflow_type: "test",
            key: "test.key", lane: "raw"
          )
          raise "rollback"
        end
      end.to raise_error("rollback")
      expect(db.connection[:workflow_events].count).to eq(0)
    end
  end

  describe "#close" do
    it "disconnects without error" do
      db.setup!
      expect { db.close }.not_to raise_error
    end
  end
end
