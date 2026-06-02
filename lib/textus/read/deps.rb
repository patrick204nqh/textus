module Textus
  module Read
    class Deps
      extend Textus::Contract::DSL

      verb     :deps
      summary  "List the keys a derived entry depends on (its projection/external sources)."
      surfaces :cli, :ruby, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted key of the derived entry whose source keys you want"

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call(key)
        { "key" => key, "deps" => sources_for(key) }
      end

      private

      def sources_for(key)
        entry = @manifest.data.entries.find { |e| e.key == key }
        return [] unless entry.is_a?(Textus::Manifest::Entry::Derived)

        src = entry.source
        result = if src.is_a?(Textus::Manifest::Entry::Derived::Projection)
                   Array(src.select).compact
                 elsif src.is_a?(Textus::Manifest::Entry::Derived::External)
                   Array(src.sources).compact
                 else
                   []
                 end
        result.uniq
      end
    end
  end
end
