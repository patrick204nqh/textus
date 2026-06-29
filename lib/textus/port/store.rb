# frozen_string_literal: true

require "fileutils"
require "sqlite3"

module Textus
  module Port
    # SQLite-backed runtime store for textus state. Owns the connection,
    # schema setup, WAL mode, and transaction boundary for the index and queue.
    class Store
      attr_reader :path, :connection

      def initialize(root:)
        @path = Textus::Store::Layout.new(root).store_db_path
        FileUtils.mkdir_p(File.dirname(@path))
        @connection = SQLite3::Database.new(@path)
        @connection.results_as_hash = true
      end

      def execute(sql, params = [])
        @connection.execute(sql, params)
      end

      def query_value(sql, params = [])
        @connection.get_first_value(sql, params)
      end

      def setup!
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA foreign_keys=ON")
        connection.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS entries (
            key        TEXT PRIMARY KEY,
            lane       TEXT NOT NULL,
            format     TEXT NOT NULL,
            etag       TEXT,
            content    TEXT,
            extra      TEXT,
            indexed_at TEXT NOT NULL
          ) STRICT;

          CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
            key, lane, content,
            content=entries, content_rowid=rowid
          );

          CREATE TABLE IF NOT EXISTS jobs (
            id               TEXT PRIMARY KEY,
            type             TEXT NOT NULL,
            args             TEXT NOT NULL,
            state            TEXT NOT NULL DEFAULT 'ready',
            role             TEXT NOT NULL,
            attempts         INTEGER NOT NULL DEFAULT 0,
            max_attempts     INTEGER NOT NULL DEFAULT 3,
            errors           TEXT,
            lease            TEXT,
            created_at       TEXT NOT NULL,
            updated_at       TEXT NOT NULL
          ) STRICT;

          CREATE INDEX IF NOT EXISTS idx_jobs_state ON jobs(state);
          CREATE INDEX IF NOT EXISTS idx_entries_lane ON entries(lane);

          CREATE TABLE IF NOT EXISTS audit_events (
            seq          INTEGER PRIMARY KEY,
            ts           TEXT NOT NULL,
            role         TEXT NOT NULL,
            verb         TEXT NOT NULL,
            key          TEXT NOT NULL,
            etag_before  TEXT,
            etag_after   TEXT
          ) STRICT;

          CREATE INDEX IF NOT EXISTS idx_audit_events_seq ON audit_events(seq);
        SQL
        self
      end

      def insert_audit_event(seq:, ts:, role:, verb:, key:, etag_before:, etag_after:) # rubocop:disable Naming/MethodParameterName
        execute(
          "INSERT OR IGNORE INTO audit_events (seq, ts, role, verb, key, etag_before, etag_after) VALUES (?, ?, ?, ?, ?, ?, ?)",
          [seq, ts, role, verb, key, etag_before, etag_after],
        )
      end

      def audit_events_since(seq:)
        execute(
          "SELECT seq, ts, role, verb, key, etag_before, etag_after FROM audit_events WHERE seq > ? ORDER BY seq",
          [seq],
        )
      end

      def transaction
        connection.transaction
        yield
        connection.commit
      rescue StandardError
        connection.rollback if connection.transaction_active?
        raise
      end

      def close
        connection.close unless connection.closed?
      end

      def self.open(root)
        store = new(root: root)
        store.setup!
        return store unless block_given?

        yield store
      ensure
        store&.close
      end
      private :connection
    end
  end
end
