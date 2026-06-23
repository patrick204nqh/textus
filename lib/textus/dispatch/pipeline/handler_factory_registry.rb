# frozen_string_literal: true

module Textus
  module Dispatch
    class Pipeline
      # A simple registry mapping contract classes to handler factory callables.
      # The registry exposes Hash-like accessors so it can be passed around and
      # interrogated by other composition code.
      #
      # This object replaces the prior Pipeline::Builder seam. Instead of
      # inlining handler registrations into a builder, we register factory
      # callables into this registry and adapt the registry into a live
      # Dispatch::Pipeline via Textus::Dispatch::Pipeline::Adapter.
      class HandlerFactoryRegistry
        def initialize
          @map = {}
        end

        def register(contract_class, factory)
          @map[contract_class] = factory
        end

        def each(&)
          @map.each(&)
        end

        def [](contract_class)
          @map[contract_class]
        end
      end
    end
  end
end
