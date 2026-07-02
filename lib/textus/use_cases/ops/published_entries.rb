# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      class PublishedEntries < Base
        handles Dispatch::Contracts::PublishedEntries
        needs :manifest

        def call
          success(manifest.data.entries.reject { |entry| entry.publish_to.empty? }.map do |entry|
            { "key" => entry.key, "publish_to" => entry.publish_to }
          end)
        end
      end
    end
  end
end
