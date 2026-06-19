# frozen_string_literal: true

require "json"
require "time"

module Textus
  module Index
    class Builder
      def initialize(store:)
        @store = store
        @db = store.connection
      end

      def rebuild!(resolver:)
        indexed = 0
        @store.transaction do
          @db.execute("DELETE FROM entries")
          resolver.enumerate.each do |row|
            indexed += index_row(row)
          end
          @db.execute("INSERT INTO entries_fts(entries_fts) VALUES('rebuild')")
        end
        { indexed: indexed }
      end

      private

      def index_row(row)
        key = row.fetch(:key)
        path = row.fetch(:path)
        entry = row.fetch(:manifest_entry)
        return 0 unless path && File.file?(path)

        raw = File.read(path)
        parsed = Textus::Format.for(entry.format).parse(raw, path: path)
        content = content_text(parsed)
        extra = extra_json(parsed)
        @db.execute(
          "INSERT INTO entries (key, lane, format, etag, content, extra, indexed_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)",
          [key, entry.lane, entry.format.to_s, Textus::Etag.for_bytes(raw), content, extra, Time.now.utc.iso8601],
        )
        1
      end

      def content_text(parsed)
        content = parsed["content"]
        body = parsed["body"]
        parts = []
        parts << body if body
        parts << JSON.dump(content) if content
        parts.compact.join("\n")
      end

      def extra_json(parsed)
        content = parsed["content"]
        extra = {}
        if content.is_a?(Hash)
          extra["content_hash"] = content["content_hash"] if content["content_hash"]
          url = content.dig("source", "url")
          extra["url"] = url if url
        end
        JSON.dump(extra)
      end
    end
  end
end
