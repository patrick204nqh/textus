module Textus
  module Domain
    module Envelope
      module_function

      def build(key:, mentry:, path:, meta:, body:, etag:, content: nil, freshness: nil)
        {
          "protocol" => Textus::PROTOCOL,
          "key" => key,
          "lane" => mentry.lane,
          "owner" => mentry.owner,
          "path" => path,
          "format" => mentry.format,
          "uid" => extract_uid(meta),
          "sources" => extract_sources(meta),
          "etag" => etag,
          "schema_ref" => mentry.schema,
          "_meta" => meta,
          "body" => body,
          "content" => content,
          "freshness" => freshness,
        }
      end

      def extract_uid(meta)
        v = meta.is_a?(Hash) ? meta["uid"] : nil
        v.is_a?(String) ? v : nil
      end

      def extract_sources(meta)
        v = meta.is_a?(Hash) ? meta["sources"] : nil
        return nil unless v.is_a?(Array) && !v.empty?

        valid = v.select { |s| s.is_a?(String) || (s.is_a?(Hash) && s["key"].is_a?(String)) }
        valid.empty? ? nil : valid
      end

      def to_wire(envelope)
        h = {
          "protocol" => envelope["protocol"],
          "key" => envelope["key"],
          "lane" => envelope["lane"],
          "owner" => envelope["owner"],
          "path" => envelope["path"],
          "format" => envelope["format"],
          "_meta" => envelope["_meta"],
          "body" => envelope["body"],
          "etag" => envelope["etag"],
          "schema_ref" => envelope["schema_ref"],
          "uid" => envelope["uid"],
        }
        h["sources"] = envelope["sources"] if envelope["sources"]
        h["content"] = envelope["content"] unless envelope["content"].nil?
        h
      end

      def stale?(freshness)
        freshness.is_a?(Hash) && freshness["stale"] == true
      end
    end
  end
end
