# frozen_string_literal: true

require "json"

module Textus
  module Index
    class Lookup
      def initialize(store:)
        @store = store
        @db = store.connection
      end

      def search(query, lane: nil)
        return [] if query.to_s.strip.empty?

        clauses = ["entries_fts MATCH ?"]
        params = [query]
        if lane
          clauses << "entries.lane = ?"
          params << lane
        end
        conditions = "WHERE #{clauses.join(" AND ")}"
        @db.execute(
          "SELECT entries.key, entries.lane, entries.format, entries.etag, bm25(entries_fts) AS rank
             FROM entries_fts JOIN entries ON entries_fts.rowid = entries.rowid
           #{conditions}
           ORDER BY rank",
          params,
        )
      rescue SQLite3::SQLException
        []
      end

      def find_by_hash(content_hash)
        return nil if content_hash.to_s.empty?

        find_extra("content_hash", content_hash)
      end

      def find_by_url(url)
        return nil if url.to_s.empty?

        find_extra("url", url)
      end

      private

      def find_extra(name, value)
        @db.execute("SELECT key, extra FROM entries ORDER BY indexed_at DESC").each do |row|
          extra = JSON.parse(row["extra"] || "{}")
          return row["key"] if extra[name] == value
        end
        nil
      rescue SQLite3::SQLException
        nil
      end
    end
  end
end
