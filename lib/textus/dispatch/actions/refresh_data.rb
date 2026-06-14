# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class RefreshData < Base
        extend Textus::Contract::DSL

        verb :refresh_data
        summary "Refresh intake data by converging through the pipeline"
        arg :key, String, required: true, description: "entry key to refresh"

        BURN = :async

        def initialize(key:)
          super()
          @key = key
        end

        def args = { key: @key }

        def call(container:, call:)
          Textus::Dispatch::Pipeline::Engine.converge(
            container: container, call: call, keys: [@key],
          )
        end
      end
    end
  end
end
