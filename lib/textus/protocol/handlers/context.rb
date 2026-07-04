module Textus
  module Protocol
    module Handlers
      class Context
        def initialize(container, call:)
          @container = container
          @call = call
        end

        attr_reader :call, :container

        def manifest  = @container.manifest
        def layout    = @container.layout
        def schemas   = @container.schemas
        def workflows = @container.workflows
        def workflow_registry = @container.workflow_registry
      end
    end
  end
end
