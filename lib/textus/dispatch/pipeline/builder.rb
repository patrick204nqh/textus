# frozen_string_literal: true

module Textus
  module Dispatch
    class Pipeline
      # Builder composes handler factories into a HandlerRegistry and
      # returns a Pipeline instance. The builder keeps composition local to
      # the module so the public Pipeline interface remains small.
      class Builder
        def initialize(container)
          @container = container
          @registrations = []
        end

        # factory is a callable that receives the container and returns a
        # handler instance. Accepting a factory keeps registration
        # flexible: callers can pass lambdas that construct handlers with
        # specific named args.
        def register(contract_class, factory)
          @registrations << [contract_class, factory]
        end

        def build(middleware: [])
          registry = HandlerRegistry.new
          @registrations.each do |contract_class, factory|
            handler = factory.call(@container)
            registry.register(contract_class, handler)
          end

          Dispatch::Pipeline.new(registry: registry, container: @container, middleware: middleware)
        end
      end
    end
  end
end
