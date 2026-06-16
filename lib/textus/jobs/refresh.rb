# frozen_string_literal: true

module Textus
  module Jobs
    class Refresh < Base
      TYPE = "refresh"

      def initialize(key:)
        super()
        @key = key
      end

      def args = { key: @key }

      def call(container:, call:)
        Textus::Produce::Engine.converge(container: container, call: call, keys: [@key])
      end
    end
  end
end
