module Textus
  module Action
    module Background
      class Refresh < Action::Base
        TYPE = "refresh"

        def initialize(key:)
          super()
          @key = key
        end

        def args = { key: @key }

        def call(container:, call:)
          Textus::Pipeline::Engine.converge(container: container, call: call, keys: [@key])
        end
      end
    end
  end
end
