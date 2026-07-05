require "timeout"
require "concurrent"

module Textus
  module Workflow
    class StepExecutor
      DEFAULT_TIMEOUT = 30
      CONCURRENCY_ADAPTER = Textus::Infra::Adapters::ConcurrencyAdapter.new

      class StepScope
        include Textus::Workflow::Helpers

        def initialize(data, ctx)
          @data = data
          @ctx  = ctx
        end

        def call(callable)
          instance_exec(@data, @ctx, &callable)
        end
      end

      def execute(steps, ctx)
        data = nil
        steps.each { |step| data = execute_one(step, data, ctx) }
        data
      end

      private

      def execute_one(step, data, ctx)
        case step
        when DSL::Step then execute_single(step, data, ctx)
        when DSL::Parallel then execute_parallel(step, ctx)
        else raise ArgumentError.new("unknown step type: #{step.class}")
        end
      end

      def execute_single(step, data, ctx)
        scope = StepScope.new(data, ctx)
        timeout = step.timeout || DEFAULT_TIMEOUT
        Timeout.timeout(timeout) { scope.call(step.callable) }
      rescue Timeout::Error => e
        raise StepFailed.new(step.name, e)
      rescue Textus::Error
        raise
      rescue StandardError => e
        raise StepFailed.new(step.name, e)
      end

      def execute_parallel(parallel, ctx)
        scope = StepScope.new(nil, ctx)
        promises = parallel.steps.map do |step|
          CONCURRENCY_ADAPTER.future do
            timeout = step.timeout || DEFAULT_TIMEOUT
            Timeout.timeout(timeout) { scope.call(step.callable) }
          end
        end

        results = CONCURRENCY_ADAPTER.zip_futures(*promises).value!
        failures = []
        outputs = {}
        results.each_with_index do |result, i|
          step = parallel.steps[i]
          if result.fulfilled?
            outputs[step.name] = result.value!
          else
            failures << { step: step.name, error: result.reason.message }
          end
        end

        raise ParallelStepFailed.new(failures) unless failures.empty?

        outputs
      end
    end
  end
end
