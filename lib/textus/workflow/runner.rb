module Textus
  module Workflow
    class ParallelStepFailed < Textus::Error
      attr_reader :failures

      def initialize(failures)
        @failures = failures
        msgs = failures.map { |f| "#{f[:step]}: #{f[:error]}" }.join("; ")
        super(:workflow_parallel_step_failed, "parallel step(s) failed: #{msgs}")
      end
    end

    class Runner
      Context = Data.define(:key, :entry, :config, :lane, :container, :call) do
        def manifest    = container.manifest
        def layout      = container.layout
        def schemas     = container.schemas
        def file_system = container.store.file_system
        def read(key)   = Textus::Protocol::StoreEngine.new(file_system:, manifest:, layout:, store: container.store, schemas:).read(key:)
        def repo_root   = File.dirname(container.root)
        def store_root  = container.root
      end

      def initialize(definition, container:, call:)
        @definition = definition
        @container  = container
        @call       = call
        @publisher  = Publisher.new(container: container, call: call)
        @step_executor   = StepExecutor.new
      end

      def run(key)
        res = @container.manifest.resolver.resolve(key)
        ctx = Context.new(
          key: key,
          entry: res.entry,
          config: {}.freeze,
          lane: res.entry.lane.to_s,
          container: @container,
          call: @call,
        )
        data = @step_executor.execute(@definition.steps, ctx)
        @publisher.publish(key, data, ctx, @definition) if data
        data
      end
    end
  end
end
