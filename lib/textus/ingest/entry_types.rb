module Textus
  module Ingest
    module EntryTypes
      def self.for(kind)
        registry[kind] or raise ArgumentError, "unknown ingest kind: #{kind}"
      end

      def self.registry
        @registry ||= {
          "link"  => Link,
          "asset" => Asset,
          "text"  => Text,
        }
      end

      class Link
        REQUIRED = %w[url ingested_at].freeze
      end

      class Asset
        REQUIRED = %w[url ingested_at mime_type checksum].freeze
      end

      class Text
        REQUIRED = %w[url ingested_at].freeze
      end
    end
  end
end
