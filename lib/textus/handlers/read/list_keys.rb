module Textus
  module Handlers
    module Read
      class ListKeys
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(command, _call)
          rows = @manifest.resolver.enumerate(prefix: command.prefix)
          rows = rows.select { |row| row[:manifest_entry].lane == command.lane } if command.lane
          Value::Result.success(rows.map do |row|
            { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] }
          end)
        end
      end
    end
  end
end
