# frozen_string_literal: true

require "fileutils"
require "sqlite3"

module Textus
  module Port
    # SQLite-backed runtime store for textus state. Owns the connection,
    # schema setup, WAL mode, and transaction boundary for the index and queue.
    class Store
      attr_reader :path, :connection

      SQLITE_ADAPTER = Textus::DependencyAdapters::SqliteAdapter.new

      def initialize(root:)
        @path = Textus::Store::Layout.new(root).store_db_path
        FileUtils.mkdir_p(File.dirname(@path))
        @connection = SQLITE_ADAPTER.open(@path)
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

          CREATE TABLE IF NOT EXISTS link_edges (
            from_key TEXT NOT NULL,
            to_key   TEXT NOT NULL,
            PRIMARY KEY (from_key, to_key)
          ) STRICT;

          CREATE INDEX IF NOT EXISTS idx_link_edges_to ON link_edges(to_key);
          CREATE INDEX IF NOT EXISTS idx_link_edges_from ON link_edges(from_key);
        SQL
        # Idempotent migration: add schema_ref column if missing (existing stores).
        execute("ALTER TABLE entries ADD COLUMN schema_ref TEXT") rescue nil # rubocop:disable Style/RescueModifier
        self
      end

      def search_entries(q: nil, schema: nil, lane: nil, prefix: nil) # rubocop:disable Naming/MethodParameterName
        return nil if q.nil? && schema.nil?

        if q
          fts_search(q: q, schema: schema, lane: lane, prefix: prefix)
        else
          schema_search(schema: schema, lane: lane, prefix: prefix)
        end
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

      def fts_search(q:, schema:, lane:, prefix:) # rubocop:disable Naming/MethodParameterName
        sql    = "SELECT e.key, e.lane, e.schema_ref FROM entries e JOIN entries_fts fts ON e.rowid = fts.rowid WHERE entries_fts MATCH ?"
        params = [q]
        sql += " AND e.lane = ?"                  and params << lane                       if lane
        sql += " AND e.schema_ref = ?"            and params << schema                     if schema
        sql += " AND (e.key = ? OR e.key LIKE ?)" and params.push(prefix, "#{prefix}.%")   if prefix
        execute(sql, params)
      end
      private :fts_search

      def schema_search(schema:, lane:, prefix:)
        sql    = "SELECT key, lane, schema_ref FROM entries WHERE schema_ref = ?"
        params = [schema]
        sql += " AND lane = ?"                    and params << lane                       if lane
        sql += " AND (key = ? OR key LIKE ?)"     and params.push(prefix, "#{prefix}.%")   if prefix
        execute(sql, params)
      end
      private :schema_search
    end
  end
end
