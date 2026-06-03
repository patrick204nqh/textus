module Textus
  module Read
    class Published
      extend Textus::Contract::DSL

      verb     :published
      summary  "List all entries that declare a publish_to target."
      surfaces :cli
      cli      "published"

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call
        @manifest.data.entries.reject { |e| e.publish_to.empty? }.map do |e|
          { "key" => e.key, "publish_to" => e.publish_to }
        end
      end
    end
  end
end
