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
      CONCURRENCY_ADAPTER = Textus::DependencyAdapters::ConcurrencyAdapter.new

      def initialize(definition, container:, call:)
        @definition = definition
        @container  = container
        @call       = call
      end

      def run(key)
        ctx  = build_context(key)
        data = execute_steps(ctx)
        publish(key, data, ctx)
        data
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

      # Validation steps collect issues instead of raising on failure.
      def execute_validate(step, data, ctx)
        step.callable.call(data, ctx)
      end

      class StepScope
        include Helpers

        def initialize(data, ctx, runner)
          @data = data
          @ctx  = ctx
          @container = ctx.container
          @call = ctx.call
        end

        def call(callable)
          instance_exec(@data, @ctx, &callable)
        end
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

      public

      # Run validation across ALL matching entries (multi-key scan).
      # Returns { workflow:, total:, passed:, issues: }
      def validate_all
        keys = if @definition.multi_match?
                 all_matching_keys
               else
                 @container.manifest.data.entries.select do |e|
                   @definition.match?(e.key)
                 end.map(&:key)
               end
        all_issues = []
        keys.each do |key|
          ctx = build_context(key)
          each_validate_step(ctx).each { |issue| all_issues << issue.merge("key" => key) }
        end
        {
          "workflow" => @definition.name,
          "total" => keys.size,
          "passed" => keys.size - all_issues.group_by { |i| i["key"] }.size,
          "issues" => all_issues,
        }
      end

      private

      def all_matching_keys
        prefix = @definition.match_pattern.sub(/\.\*\*$/, "")
        rows = @container.manifest.resolver.enumerate
        rows.select { |r| r[:key].start_with?(prefix) }.map { |r| r[:key] }
      end

      def each_validate_step(ctx)
        @definition.validate_steps.flat_map { |step| step.callable.call(nil, ctx) }
      end

      def publish(key, data, ctx)
        targets = @definition.publish_targets
        if targets.any?
          write_and_publish(key, data, ctx, targets)
          return
        end

        blk = @definition.publish_block
        return blk.call(data, ctx) if blk && blk != :default

        built_in_publish(key, data, ctx)
      end

      def write_and_publish(key, data, ctx, targets)
        normalized = Textus::Format.data_to_payload(data, ctx.entry.format)
        @container.writer.put(key, mentry: ctx.entry,
                                  payload: Textus::Value::Payload.new(**normalized), call: @call)

        targets.each do |target|
          attrs = { "to" => target.to, "template" => target.template,
                    "tree" => target.tree }
          attrs["inject_boot"] = true if target.inject_boot
          pub_target = Textus::Manifest::Policy::PublishTarget.new(attrs)
          pctx = Textus::Manifest::Entry::Base::PublishContext.new(
            container: @container, call: @call,
            reader: @container.reader.method(:read)
          )
          entry = ctx.entry.with_publish_targets([pub_target])
          entry.publish_via(pctx)
        end
      end

      def built_in_publish(key, data, ctx)
        normalized = Textus::Format.data_to_payload(data, ctx.entry.format)
        guard_map = @container.manifest.rules.for(key).guard
        rule_preds = guard_map ? Array(guard_map["converge"]) : []
        Textus::Manifest::Policy::Predicates.evaluate(
          manifest: @container.manifest, schemas: @container.schemas,
          action: :converge, actor: @call.role, key: key,
          rule_predicates: rule_preds
        )
        @container.writer.put(key, mentry: ctx.entry,
                                  payload: Textus::Value::Payload.new(**normalized), call: @call)

        entry = @container.manifest.resolver.resolve(key).entry
        return unless entry.publish_tree || !Array(entry.publish_to).empty?

        pctx = Textus::Manifest::Entry::Base::PublishContext.new(
          container: @container, call: @call,
          reader: @container.reader.method(:read),
        )
        entry.publish_via(pctx)
      end
    end
  end
end
