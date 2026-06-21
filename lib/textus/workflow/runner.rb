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
        Gate::Auth.new(@container).check_action!(action: :converge, actor: @call.role, key: key)
        Textus::Store::Envelope::Writer.from(container: @container, call: @call).put(
          key,
          mentry: ctx.entry,
          payload: Textus::Store::Envelope::Writer::Payload.new(**normalized),
        )
        publish_external(key, ctx)
      end

      def publish_external(key, ctx)
        entry = ctx.entry
        return unless entry.publish_tree || !Array(entry.publish_to).empty?

        entry_path = @container.manifest.resolver.resolve(key).path
        return unless entry.publish_tree || File.exist?(entry_path)

        reader = Textus::Store::Envelope::Reader.from(container: @container)
        pctx   = Textus::Manifest::Entry::Base::PublishContext.new(
          container: @container, call: @call, reader: reader.method(:read),
        )
        entry.publish_via(pctx)
      end

    end
  end
end
