# frozen_string_literal: true

require "securerandom"

module Textus
  module Meta
    SOURCE_FIELDS = %w[raw].freeze
    NO_META_FORMATS = %w[text].freeze

    FIELDS = {
      "uid" => {
        inject: lambda { |meta, content, existing_meta|
          m = meta.is_a?(Hash) ? meta.dup : {}
          existing = existing_meta.is_a?(Hash) ? existing_meta["uid"] : nil
          m["uid"] = existing || Textus::Value::Uid.mint unless m["uid"].is_a?(String) && !m["uid"].empty?
          [m, content]
        },
      },
      "sources" => {
        inject: lambda { |meta, content, existing_meta|
          m = meta.is_a?(Hash) ? meta.dup : {}
          existing = existing_meta.is_a?(Hash) ? existing_meta["sources"] : nil

          if m.key?("sources")
            raise Textus::BadContent.new(nil, "_meta.sources must be an array") unless m["sources"].is_a?(Array)

            m["sources"] = m["sources"].map { |s| validate_source_shape!(s) }
          elsif existing.is_a?(Array) && !existing.empty?
            m["sources"] = existing
          end

          [m, content]
        },
      },
    }.freeze

    def self.inject_all(meta, content, existing_meta = {}, format: nil)
      return [meta, content] if NO_META_FORMATS.include?(format)

      FIELDS.each_value do |field|
        meta, content = field[:inject].call(meta, content, existing_meta)
      end

      [meta, content]
    end

    def self.validate_source_shape!(src)
      raise Textus::BadContent.new(nil, "each source must be a hash") unless src.is_a?(Hash)

      raw = src["raw"]
      unless raw.is_a?(String) && raw.match?(/\Araw\./)
        raise Textus::BadContent.new(nil, "source.raw must be a string starting with 'raw.'")
      end

      extra = src.keys - SOURCE_FIELDS
      raise Textus::BadContent.new(nil, "unknown source key(s): #{extra.join(", ")}") if extra.any?

      src
    end
  end
end
