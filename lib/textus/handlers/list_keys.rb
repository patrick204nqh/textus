module Textus
  module Handlers
    class ListKeys
      def initialize(manifest:)
        @manifest = manifest
      end

      def call(command, call)
        rows = @manifest.resolver.enumerate(prefix: command.prefix)
        rows = rows.select { |row| row[:manifest_entry].lane == command.lane } if command.lane
        Result.success(rows.map { |row|
          { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] }
        })
      end
    end
  end
end
