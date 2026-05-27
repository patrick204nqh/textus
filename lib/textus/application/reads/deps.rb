module Textus
  module Application
    module Reads
      class Deps
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(key)
          entry = @manifest.entries.find { |e| e.key == key } or return []
          result = Array(entry.projection&.fetch("select", nil)).dup
          Array(entry.generator&.fetch("sources", nil)).each { |s| result << s }
          result.uniq
        end
      end
    end
  end
end
