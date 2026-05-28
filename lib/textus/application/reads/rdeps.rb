module Textus
  module Application
    module Reads
      class Rdeps
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(key)
          @manifest.data.entries.each_with_object([]) do |e, acc|
            next unless e.is_a?(Textus::Manifest::Entry::Derived)

            src = e.source
            sources = if src.is_a?(Textus::Manifest::Entry::Derived::Projection)
                        Array(src.select).compact
                      elsif src.is_a?(Textus::Manifest::Entry::Derived::External)
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
end
