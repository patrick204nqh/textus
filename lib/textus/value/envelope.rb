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
      attribute :schema_ref, Types::String.optional
      attribute :meta,       Types::Hash.default({}.freeze)
      attribute :body,       Types::String.optional
      attribute :content,    Types::Any.optional
      attribute :freshness,  Types::Any.optional

      # rubocop:disable Metrics/ParameterLists
      def self.build(key:, mentry:, path:, meta:, body:, etag:, content: nil, freshness: nil)
        # rubocop:enable Metrics/ParameterLists
        new(
          protocol: Textus::PROTOCOL,
          key: key,
          lane: mentry.lane,
          owner: mentry.owner,
          path: path,
          format: mentry.format,
          uid: extract_uid(meta),
          etag: etag,
          schema_ref: mentry.schema,
          meta: meta,
          body: body,
          content: content,
          freshness: freshness,
        )
      end

      def self.extract_uid(meta)
        v = meta.is_a?(Hash) ? meta["uid"] : nil
        v.is_a?(String) ? v : nil
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
