# frozen_string_literal: true

require "dry-struct"

module Textus
  module Value
    class Envelope < Dry::Struct
      attribute :protocol,   Types::String
      attribute :key,        Types::String
      attribute :lane,       Types::String
      attribute :owner,      Types::String.optional
      attribute :path,       Types::String
      attribute :format,     Types::FormatName
      attribute :etag,       Types::String
      attribute :uid,        Types::String.optional
      attribute :sources,    Types::Array.of(Types::Any).optional
      attribute :schema_ref, Types::String.optional
      attribute :meta,       Types::Hash.default({}.freeze)
      attribute :body,       Types::String.optional
      attribute :content,    Types::Any.optional
      attribute :freshness,  Types::Any.optional

      def self.build(key:, mentry:, path:, meta:, body:, etag:, content: nil, freshness: nil)
        raw = Domain::Envelope.build(
          key:, mentry:, path:, meta:, body:, etag:, content:, freshness:,
        )
        new(
          protocol: raw["protocol"],
          key: raw["key"],
          lane: raw["lane"],
          owner: raw["owner"],
          path: raw["path"],
          format: raw["format"],
          uid: raw["uid"],
          sources: raw["sources"],
          etag: raw["etag"],
          schema_ref: raw["schema_ref"],
          meta: raw["_meta"],
          body: raw["body"],
          content: raw["content"],
          freshness: raw["freshness"],
        )
      end

      def with(**attrs) = self.class.new(to_h.merge(attrs))

      def to_h_for_wire
        h = {
          "protocol" => protocol,
          "key" => key,
          "lane" => lane,
          "owner" => owner,
          "path" => path,
          "format" => format,
          "_meta" => meta,
          "body" => body,
          "etag" => etag,
          "schema_ref" => schema_ref,
          "uid" => uid,
        }
        h["sources"] = sources if sources
        h["content"] = content unless content.nil?
        freshness&.to_h_for_wire&.each { |k, v| h[k] = v }
        h
      end

      def stale?
        return false if freshness.nil?

        freshness.stale == true
      end

      def fetching?
        return false if freshness.nil?

        freshness.fetching == true
      end
    end
  end
end
