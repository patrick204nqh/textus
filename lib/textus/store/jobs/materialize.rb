# frozen_string_literal: true

module Textus
  class Store
    module Jobs
      class Materialize < Base
        TYPE = "materialize"

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
end
