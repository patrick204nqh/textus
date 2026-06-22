module Textus
  module Handlers
    class PublishedEntries
      def initialize(manifest:)
        @manifest = manifest
      end

      def call(_command, _call)
        Result.success(@manifest.data.entries.reject { |entry| entry.publish_to.empty? }.map do |entry|
          { "key" => entry.key, "publish_to" => entry.publish_to }
        end)
      end
    end
  end
end
