module Textus
  module Handlers
    class DepsEntry
      def initialize(manifest:)
        @manifest = manifest
      end

      def call(command, call)
        entry = @manifest.data.entries.find { |e| e.key == command.key }
        deps = entry&.external? ? Array(entry.source&.sources).compact : []
        Result.success("key" => command.key, "deps" => deps.uniq)
      end
    end
  end
end
