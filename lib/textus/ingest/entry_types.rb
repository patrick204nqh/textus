module Textus
  module Ingest
    module EntryTypes
      require_relative "entry_types/link"
      require_relative "entry_types/asset"
      require_relative "entry_types/text"

      module_function

      def for(kind)
        registry[kind] or raise ArgumentError, "unknown ingest kind: #{kind}"
      end

      def registry
        @registry ||= {
          "link"  => Link,
          "asset" => Asset,
          "text"  => Text,
        }.freeze
      end
    end
  end
end
