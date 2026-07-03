require "dry-struct"

module Textus
  module Protocol
    class Envelope < Dry::Struct
      attribute :protocol,   Textus::Value::Types::String
      attribute :key,        Textus::Value::Types::String
      attribute :lane,       Textus::Value::Types::String
      attribute :path,       Textus::Value::Types::String
      attribute :format,     Textus::Value::Types::FormatName
      attribute :etag,       Textus::Value::Types::String
      attribute :uid,        Textus::Value::Types::String.optional
      attribute :sources,    Textus::Value::Types::Array.of(Textus::Value::Types::Any).optional
      attribute :schema_ref, Textus::Value::Types::String.optional
      attribute :meta,       Textus::Value::Types::Hash.default({}.freeze)
      attribute :body,       Textus::Value::Types::String.optional
      attribute :content,    Textus::Value::Types::Any.optional
      attribute :freshness,  Textus::Value::Types::Any.optional

      def self.build(key:, mentry:, path:, meta:, body:, etag:, content: nil, freshness: nil)
        new(
          protocol: Textus::PROTOCOL,
          key:,
          lane: mentry.lane,
          path:,
          format: mentry.format,
          uid: extract_uid(meta),
          sources: extract_sources(meta),
          etag:,
          schema_ref: mentry.schema,
          meta: meta || {},
          body:,
          content:,
          freshness:,
        )
      end

      def with(**attrs) = self.class.new(to_h.merge(attrs))

      def to_h_for_wire
        h = {
          "protocol" => protocol, "key" => key, "lane" => lane,
          "path" => path, "format" => format, "_meta" => meta,
          "body" => body, "etag" => etag, "schema_ref" => schema_ref, "uid" => uid
        }
        h["sources"] = sources if sources
        h["content"] = content unless content.nil?
        freshness&.to_h_for_wire&.each { |k, v| h[k] = v }
        h
      end

      def stale? = freshness.is_a?(Hash) && freshness["stale"] == true

      def fetching? = freshness.is_a?(Hash) && freshness["fetching"] == true

      def self.extract_uid(meta)
        v = meta.is_a?(Hash) ? meta["uid"] : nil
        v.is_a?(String) ? v : nil
      end

      def self.extract_sources(meta)
        v = meta.is_a?(Hash) ? meta["sources"] : nil
        return nil unless v.is_a?(Array) && !v.empty?

        valid = v.select { |s| s.is_a?(String) || (s.is_a?(Hash) && s["key"].is_a?(String)) }
        valid.empty? ? nil : valid
      end
    end
  end
end
