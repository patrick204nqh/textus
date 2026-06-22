module Textus
  module Handlers
    class RdepsEntry
      def initialize(manifest:)
        @manifest = manifest
      end

      def call(command, call)
        rdeps = @manifest.data.entries.each_with_object([]) do |entry, acc|
          next unless entry.external?

          sources = Array(entry.source&.sources).compact
          acc << entry.key if sources.any? { |source| source == command.key || command.key.start_with?("#{source}.") }
        end
        Result.success("key" => command.key, "rdeps" => rdeps)
      end
    end
  end
end
