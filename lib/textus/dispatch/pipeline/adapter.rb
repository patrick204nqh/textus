# frozen_string_literal: true

module Textus
  module Dispatch
    class Pipeline
      # PipelineAdapter provides an alternate composition seam for the
      # Dispatch::Pipeline: instead of registering concrete handlers into a
      # registry, the adapter delegates handler construction to a
      # HandlerFactoryRegistry. This allows pluggable handler factories and
      # a clearer separation between registry wiring and handler
      # construction.
      class Adapter
        def initialize(container:, factory_registry:, middleware: [])
          @container = container
          @factory_registry = factory_registry
          @middleware = middleware
        end

        def call(contract, call)
          # ensure pipeline is built and delegate to its dispatch
          pipeline.dispatch(contract: contract, call: call)
        end

        def pipeline
          @pipeline ||= Dispatch::Pipeline.new(registry: build_registry, container: @container, middleware: @middleware)
        end

        private

        def build_registry
          registry = HandlerRegistry.new
          @factory_registry.each do |contract_class, factory|
            handler = factory.call(@container)
            registry.register(contract_class, handler)
          end
          registry
        end

        def build_handler_for(contract)
          factory = @factory_registry[contract]
          raise "No factory registered for #{contract}" unless factory

          factory.call(@container)
        end
      end
    end
  end
end
