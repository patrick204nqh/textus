# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      # Materializes one derived/intake entry when a dependency changes.
      class Materialize < Base
        extend Textus::Contract::DSL

        verb :materialize
        summary "Materialize derived entry by converging its pipeline"
        arg :key, String, required: true, description: "entry key to materialize"

        TYPE = "materialize"
        BURN = :async

        def initialize(key:)
          super()
          @key = key
        end

        def args = { key: @key }

        def call(container:, call:)
          Textus::Dispatch::Pipeline::Engine.converge(container: container, call: call, keys: [@key])
        end
      end
    end
  end
end
