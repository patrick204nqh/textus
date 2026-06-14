# frozen_string_literal: true

module Textus
  module Action
    module Background
      class Materialize < Action::Base
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
          result = Textus::Dispatch::Pipeline::Engine.converge(container: container, call: call, keys: [@key])
          return unless result.is_a?(Hash)

          Array(result[:failed]).each do |failure|
            container.steps.publish(
              :produce_failed,
              ctx: Textus::Step::Context.for(container: container, call: call),
              keys: [failure["key"]], error: failure["error"]
            )
          end
        end
      end
    end
  end
end
