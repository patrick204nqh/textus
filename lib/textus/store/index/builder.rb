# frozen_string_literal: true

require "json"
require "time"

module Textus
  class Store
    module Index
      class Builder
        def initialize(store:)
          @store = store
        end

        def rebuild!(resolver:)
          rows = resolver.enumerate.filter_map { |row| build_row(row) }
          now_iso = Time.now.utc.iso8601

          @store.transaction do
            @store.execute("DELETE FROM entries")
            rows.each do |data|
              @store.execute(
                "INSERT INTO entries (key, lane, format, etag, content, extra, indexed_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)",
                [data[:key], data[:lane], data[:format], data[:etag], data[:content], data[:extra], now_iso],
              )
            end
            @store.execute("INSERT INTO entries_fts(entries_fts) VALUES('rebuild')")
          end
          { indexed: rows.size }
        end

        private

        def build_row(row)
          key = row.fetch(:key)
          path = row.fetch(:path)
          entry = row.fetch(:manifest_entry)
          return nil unless path && File.file?(path)

          raw = File.read(path)
          parsed = Textus::Format.for(entry.format).parse(raw, path: path)
          {
            key: key,
            lane: entry.lane,
            format: entry.format.to_s,
            etag: Textus::Value::Etag.for_bytes(raw),
            content: content_text(parsed),
            extra: extra_json(parsed),
          }
        end

        def content_text(parsed)
          content = parsed["content"]
          body = parsed["body"]
          parts = []
          parts << body if body
          parts << JSON.dump(content) if content
          parts.join("\n")
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
end
