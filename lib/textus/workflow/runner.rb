require "timeout"
require "concurrent"

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
      DEFAULT_TIMEOUT = 30
      CONCURRENCY_ADAPTER = Textus::Infra::Adapters::ConcurrencyAdapter.new

      def initialize(definition, container:, call:)
        @definition = definition
        @container  = container
        @call       = call
        @publisher  = Publisher.new(container: container, call: call)
        @validator  = Validator.new(definition, container: container)
      end

      def run(key)
        ctx  = build_context(key)
        data = execute_steps(ctx)
        publish(key, data, ctx) if data
        data
      end

      def publish(key, data, ctx)
        @publisher.publish(key, data, ctx, @definition)
      end

      def validate_all
        @validator.validate_all
      end

      private

      def build_context(key)
        res = @container.manifest.resolver.resolve(key)
        Context.new(
          key: key,
          entry: res.entry,
          config: {}.freeze,
          lane: res.entry.lane.to_s,
          container: @container,
          call: @call,
        )
      end

      def execute_steps(ctx)
        data = nil
        @definition.steps.each { |step| data = execute_one(step, data, ctx) }
        data
      end

      def execute_one(step, data, ctx)
        case step
        when DSL::Step then execute_single(step, data, ctx)
        when DSL::ValidateStep then execute_validate(step, data, ctx)
        when DSL::Parallel then execute_parallel(step, ctx)
        else raise ArgumentError.new("unknown step type: #{step.class}")
        end
      end

      def execute_validate(step, data, ctx)
        step.callable.call(data, ctx)
      end

      def execute_single(step, data, ctx)
        scope = StepScope.new(data, ctx, self)
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
        scope = StepScope.new(nil, ctx, self)
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
