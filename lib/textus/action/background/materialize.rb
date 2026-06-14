module Textus
  module Action
    module Background
      class Materialize < Action::Base
        TYPE = "materialize"

        def initialize(key:)
          super()
          @key = key
        end

        def args = { key: @key }

        def call(container:, call:)
          result = Textus::Pipeline::Engine.converge(container: container, call: call, keys: [@key])
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
