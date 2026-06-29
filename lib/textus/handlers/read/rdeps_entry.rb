module Textus
  module Handlers
    module Read
      class RdepsEntry
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(command, _call)
          rdeps = @manifest.data.entries.each_with_object([]) do |entry, acc|
            next unless entry.external?

            sources = Array(entry.source&.sources).compact
            acc << entry.key if sources.any? { |source| source == command.key || command.key.start_with?("#{source}.") }
          end
          Value::Result.success("key" => command.key, "rdeps" => rdeps)
        end
      end
    end
  end
end
