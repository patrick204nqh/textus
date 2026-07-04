require "sequel"
require "fileutils"

module Textus
  module Infra
    class Database
      def initialize(layout:)
        @layout = layout
        @db = nil
      end

      def connection = @db

      def setup!
        path = @layout.db_path
        FileUtils.mkdir_p(File.dirname(path))
        @db = Sequel.sqlite(path)
        @db.run("PRAGMA journal_mode=WAL")
        @db.run("PRAGMA foreign_keys=ON")
        create_tables
        self
      end

      def transaction(&) = @db.transaction(&)
      def close = @db.disconnect

      private

      def create_tables
        @db.create_table?(:workflow_events) do
          primary_key :id
          String :event_type, null: false
          String :workflow_type, null: false
          String :key
          String :lane
          String :payload, text: true
          DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
          DateTime :scheduled_at
          String :state, null: false, default: "pending"
          Integer :retry_count, null: false, default: 0
          Integer :max_attempts, null: false, default: 3
          String :error, text: true
          index %i[state scheduled_at], where: "state = 'pending'"
        end

        @db.create_table?(:entries) do
          String :key, primary_key: true
          String :lane, null: false
          String :format, null: false
          String :schema
          String :content, text: true
          DateTime :indexed_at, null: false
        end

        @db.create_table?(:link_edges) do
          String :from_key, null: false
          String :to_key, null: false
          primary_key %i[from_key to_key]
          index :to_key
          index :from_key
        end

        @db.create_table?(:audit_events) do
          primary_key :seq
          String :ts, null: false
          String :role, null: false
          String :verb, null: false
          String :key, null: false
          String :etag_before
          String :etag_after
          String :correlation_id
          index :key
          index %i[role verb]
          index :correlation_id
        end

        @db.create_table?(:cursors) do
          String :role, primary_key: true
          Integer :seq, null: false, default: 0
          DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        end

        create_entries_fts
      end

      def create_entries_fts
        @db.run(<<~SQL)
          CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
            key, lane, schema, content,
            content=entries, content_rowid=rowid
          )
        SQL

        @db.run(<<~SQL)
          CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
            INSERT INTO entries_fts(rowid, key, lane, schema, content)
            VALUES (new.rowid, new.key, new.lane, new.schema, new.content);
          END
        SQL

        @db.run(<<~SQL)
          CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, key, lane, schema, content)
            VALUES ('delete', old.rowid, old.key, old.lane, old.schema, old.content);
          END
        SQL

        @db.run(<<~SQL)
          CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, key, lane, schema, content)
            VALUES ('delete', old.rowid, old.key, old.lane, old.schema, old.content);
            INSERT INTO entries_fts(rowid, key, lane, schema, content)
            VALUES (new.rowid, new.key, new.lane, new.schema, new.content);
          END
        SQL
      rescue StandardError
        nil
      end
    end
  end
end
