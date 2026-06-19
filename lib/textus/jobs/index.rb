# frozen_string_literal: true

module Textus
  module Jobs
    class Index < Base
      TYPE = "index"

      def args = {}

      def call(container:, _call:)
        store = Textus::Ports::Store.new(root: container.root).setup!
        Textus::Index::Builder.new(store: store).rebuild!(resolver: container.manifest.resolver)
      ensure
        store&.close
      end
    end
  end
end
