require "securerandom"

module Textus
  class Store
    module Envelope
      module Meta
        NO_META_FORMATS = %w[text].freeze

        FIELDS = {
          "uid" => {
            inject: lambda { |meta, content, existing_meta, **_opts|
              m = meta.is_a?(Hash) ? meta.dup : {}
              existing = existing_meta.is_a?(Hash) ? existing_meta["uid"] : nil
              m["uid"] = existing || Textus::Value::Uid.mint unless m["uid"].is_a?(String) && !m["uid"].empty?
              [m, content]
            },
          },
          "sources" => {
            inject: lambda { |meta, content, existing_meta, etag_for: nil|
              m = meta.is_a?(Hash) ? meta.dup : {}
              existing = existing_meta.is_a?(Hash) ? existing_meta["sources"] : nil

              if m.key?("sources")
                raise Textus::BadContent.new(nil, "_meta.sources must be an array") unless m["sources"].is_a?(Array)

                m["sources"] = m["sources"].map { |s| Meta.normalize_source!(s, etag_for) }
              elsif existing.is_a?(Array) && !existing.empty?
                m["sources"] = existing
              end

              [m, content]
            },
          },
        }.freeze

        def self.inject_all(meta, content, existing_meta = {}, format: nil, etag_for: nil)
          return [meta, content] if NO_META_FORMATS.include?(format)

          FIELDS.each_value do |field|
            meta, content = field[:inject].call(meta, content, existing_meta, etag_for: etag_for)
          end

          [meta, content]
        end

        def self.normalize_source!(src, etag_for)
          key = case src
                when String then src
                when Hash   then src["key"]
                end

          raise Textus::BadContent.new(nil, "each source must be a string key or { key: } object") unless key.is_a?(String)
          raise Textus::BadContent.new(nil, "each source key must be a non-empty string") if key.empty?

          etag = etag_for&.call(key)
          etag ? { "key" => key, "etag" => etag } : { "key" => key }
        end
      end
    end
  end
end
