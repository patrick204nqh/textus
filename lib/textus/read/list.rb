module Textus
  module Read
    class List
      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call(prefix: nil, zone: nil)
        rows = @manifest.resolver.enumerate(prefix: prefix)
        rows = rows.select { |r| r[:manifest_entry].zone == zone } if zone
        rows.map { |row| { "key" => row[:key], "zone" => row[:manifest_entry].zone, "path" => row[:path] } }
      end
    end
  end
end
