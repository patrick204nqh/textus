# frozen_string_literal: true

module Textus
  module Jobs
    class Index < Base
      TYPE = "index"

      def args = {}

      def call(container:, call:) # rubocop:disable Lint/UnusedMethodArgument
        Textus::Port::Store.open(container.root) do |store|
          Textus::Index::Builder.new(store: store).rebuild!(resolver: container.manifest.resolver)
        end
      end
    end
  end
end
