module Textus
  module Application
    module Reads
      class List
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(prefix: nil, zone: nil)
          rows = @manifest.enumerate(prefix: prefix)
          rows = rows.select { |r| r[:manifest_entry].zone == zone } if zone
          rows.map { |row| { "key" => row[:key], "zone" => row[:manifest_entry].zone, "path" => row[:path] } }
        end
      end
    end
  end
end
