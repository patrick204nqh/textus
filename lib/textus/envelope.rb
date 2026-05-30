# frozen_string_literal: true

module Textus
  Envelope = Data.define(
    :protocol, :key, :zone, :owner, :path, :format,
    :uid, :etag, :schema_ref, :meta, :body, :content, :freshness
  ) do
    # rubocop:disable Metrics/ParameterLists
    def self.build(key:, mentry:, path:, meta:, body:, etag:, content: nil, freshness: nil)
      # rubocop:enable Metrics/ParameterLists
      new(
        protocol: Textus::PROTOCOL,
        key: key,
        zone: mentry.zone,
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

    def to_h_for_wire
      h = {
        "protocol" => protocol,
        "key" => key,
        "zone" => zone,
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
