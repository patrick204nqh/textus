require "timeout"

module Textus
  module Workflow
    class Runner
      DEFAULT_TIMEOUT = 30

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
        timeout = step.timeout || DEFAULT_TIMEOUT
        Timeout.timeout(timeout) { step.callable.call(data, ctx) }
      rescue Timeout::Error => e
        raise StepFailed.new(step.name, e)
      rescue Textus::Error
        raise
      rescue StandardError => e
        raise StepFailed.new(step.name, e)
      end

      def publish(key, data, ctx)
        blk = @definition.publish_block
        return blk.call(data, ctx) if blk && blk != :default

        built_in_publish(key, data, ctx)
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
        Textus::Store::Entry::Writer.from(container: @container, call: @call).put(
          key,
          mentry: ctx.entry,
          payload: Textus::Value::Payload.new(**normalized),
        )
        Textus::Produce::Publisher.call(container: @container, call: @call, key: key)
      end
    end
  end
end
