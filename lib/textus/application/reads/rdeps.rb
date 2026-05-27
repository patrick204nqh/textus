module Textus
  module Application
    module Reads
      class Rdeps
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(key)
          @manifest.entries.each_with_object([]) do |e, acc|
            sources = Array(e.projection&.fetch("select", nil)) + Array(e.generator&.fetch("sources", nil))
            acc << e.key if sources.any? { |s| s == key || key.start_with?("#{s}.") }
          end
        end
      end
    end
  end
end
