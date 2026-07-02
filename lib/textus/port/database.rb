require "fileutils"

module Textus
  module Port
    class Database
      module Interface
        def connection = raise NotImplementedError
        def setup! = raise NotImplementedError
        def transaction(&) = raise NotImplementedError
        def close = raise NotImplementedError
      end
      include Interface

      SEQUEL_ADAPTER = Textus::DependencyAdapters::SequelAdapter.new

      def initialize(root:)
        @layout = Textus::Store::Layout.new(root)
      end

      def setup!
        FileUtils.mkdir_p(File.dirname(@layout.store_db_path))
        @db = SEQUEL_ADAPTER.connect(@layout.store_db_path)
        @db.run("PRAGMA journal_mode=WAL")
        @db.run("PRAGMA foreign_keys=ON")
        create_tables
        self
      end

      def connection = @db
      def transaction(&) = @db.transaction(&)
      def close = @db.disconnect

      private

      def create_tables
        @db.create_table?(:events) do
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
          Integer :seq, primary_key: true
          DateTime :ts, null: false
          String :role, null: false
          String :verb, null: false
          String :key, null: false
          String :etag_before
          String :etag_after
          index :seq
        end

        begin
          @db.run(<<~SQL)
            CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
              key, lane, content,
              content=entries, content_rowid=rowid
            )
          SQL
        rescue StandardError
          nil
        end
      end
    end
  end
end
