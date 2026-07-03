require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Infra::Database do
  subject(:db) { described_class.new(root: tmpdir) }
  let(:tmpdir) { Dir.mktmpdir }
  after do
    db.close rescue nil
    FileUtils.rm_rf(tmpdir)
  end

  describe "#setup!" do
    it "creates the database file" do
      db.setup!
      expect(File).to exist(File.join(tmpdir, ".state", "store.db"))
    end

    it "creates events table" do
      db.setup!
      expect(db.connection.table_exists?(:events)).to be true
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
        db.connection[:events].insert(
          event_type: "test", workflow_type: "test",
          key: "test.key", lane: "raw"
        )
      end
      expect(db.connection[:events].count).to eq(1)
    end

    it "rolls back on error" do
      db.setup!
      expect do
        db.transaction do
          db.connection[:events].insert(
            event_type: "test", workflow_type: "test",
            key: "test.key", lane: "raw"
          )
          raise "rollback"
        end
      end.to raise_error("rollback")
      expect(db.connection[:events].count).to eq(0)
    end
  end

  describe "#close" do
    it "disconnects without error" do
      db.setup!
      expect { db.close }.not_to raise_error
    end
  end
end
