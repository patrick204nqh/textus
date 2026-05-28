module Textus
  module Application
    module Reads
      class Deps
        def initialize(ports:)
          @manifest = ports.manifest
        end

        def call(key)
          entry = @manifest.data.entries.find { |e| e.key == key } or return []
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
end
