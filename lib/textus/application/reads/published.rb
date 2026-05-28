module Textus
  module Application
    module Reads
      class Published
        def initialize(manifest:)
          @manifest = manifest
        end

        def call
          @manifest.data.entries.reject { |e| e.publish_to.empty? }.map do |e|
            { "key" => e.key, "publish_to" => e.publish_to }
          end
        end
      end
    end
  end
end
