# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      # Materializes one derived/intake entry when a dependency changes.
      class Materialize < Base
        TYPE = "materialize"
        BURN = :async

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
