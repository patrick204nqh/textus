# frozen_string_literal: true

module Textus
  class Store
    module Jobs
      class Materialize < Base
        TYPE = "materialize"

        def self.call(container:, call:, key:)
          Textus::Produce::Engine.converge(container: container, call: call, keys: [key])
        end
      end
    end
  end
end
