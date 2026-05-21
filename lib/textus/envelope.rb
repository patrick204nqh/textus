# frozen_string_literal: true

module Textus
  module Envelope
    # rubocop:disable Metrics/ParameterLists
    def self.build(key:, mentry:, path:, meta:, body:, etag:, content: nil)
      # rubocop:enable Metrics/ParameterLists
      env = {
        "protocol" => PROTOCOL,
        "key" => key,
        "zone" => mentry.zone,
        "owner" => mentry.owner,
        "path" => path,
        "format" => mentry.format,
        "_meta" => meta,
        "body" => body,
        "etag" => etag,
        "schema_ref" => mentry.schema,
        "uid" => extract_uid(meta),
      }
      env["content"] = content unless content.nil?
      env
    end

    def self.extract_uid(meta)
      v = meta.is_a?(Hash) ? meta["uid"] : nil
      v.is_a?(String) ? v : nil
    end
  end
end
