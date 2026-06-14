# frozen_string_literal: true

module Textus
  module Action
    module Background
      class Refresh < Action::Base
        extend Textus::Contract::DSL

        verb :refresh
        summary "Refresh intake data by converging through the pipeline"
        arg :key, String, required: true, description: "entry key to refresh"

        TYPE = "refresh"
        BURN = :async

        def initialize(key:)
          super()
          @key = key
        end

        def args = { key: @key }

        def call(container:, call:)
          Textus::Pipeline::Engine.converge(
            container: container, call: call, keys: [@key],
          )
        end
      end
    end
  end
end
