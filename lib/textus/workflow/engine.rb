module Textus
  module Workflow
    class Engine
      def initialize(registry:, workflow_queue:, container:, call:, reader:)
        @registry = registry
        @workflow_queue = workflow_queue
        @container = container
        @call = call
        @reader = reader
      end

      def run
        Scheduler.new(
          registry: @registry,
          workflow_queue: @workflow_queue,
          reader: @reader,
        ).seed_expired

        Queue.new(
          @workflow_queue,
          registry: @registry,
          container: @container,
          call: @call,
        ).drain
      end
    end
  end
end
