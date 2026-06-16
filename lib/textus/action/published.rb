# frozen_string_literal: true

module Textus
  module Action
    class Published < Base
      extend Textus::Contract::DSL

      verb :published
      summary "List all entries that declare a publish_to target."
      surfaces :cli
      cli "published"


      def args
        {}
      end

      def call(container:, **)
        container.manifest.data.entries.reject { |entry| entry.publish_to.empty? }.map do |entry|
          { "key" => entry.key, "publish_to" => entry.publish_to }
        end
      end
    end
  end
end
