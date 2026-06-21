# frozen_string_literal: true

module Textus
  class Store
    module Jobs
      class Index < Base
        TYPE = "index"

        def self.call(container:, call:) # rubocop:disable Lint/UnusedMethodArgument
          Textus::Store::Index::Builder.new(store: container.job_store).rebuild!(resolver: container.manifest.resolver)
        end
      end
    end
  end
end
