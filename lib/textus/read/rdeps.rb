module Textus
  module Read
    class Rdeps
      extend Textus::Contract::DSL

      verb     :rdeps
      summary  "List the derived entries that depend on a key (reverse deps / impact set)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted key whose dependents (what would be stranded if it moved) you want"

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call(key)
        { "key" => key, "rdeps" => dependents_of(key) }
      end

      private

      def dependents_of(key)
        @manifest.data.entries.each_with_object([]) do |e, acc|
          next unless e.derived?

          src = e.source
          sources = if src.projection?
                      Array(src.select).compact
                    elsif src.external?
                      Array(src.sources).compact
                    else
                      []
                    end
          acc << e.key if sources.any? { |s| s == key || key.start_with?("#{s}.") }
        end
      end
    end
  end
end
