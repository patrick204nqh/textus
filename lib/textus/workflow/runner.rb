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
          key:    key,
          entry:  res.entry,
          config: (res.entry.config || {}).freeze,
          lane:   res.entry.lane.to_s,
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
        raise Errors::StepFailed.new(step.name, e)
      rescue Textus::Error
        raise
      rescue StandardError => e
        raise Errors::StepFailed.new(step.name, e)
      end

      def publish(key, data, ctx)
        blk = @definition.publish_block
        return blk.call(data, ctx) if blk && blk != :default

        built_in_publish(key, data, ctx)
      end

      def built_in_publish(key, data, ctx)
        normalized = normalize(data, ctx.entry.format)
        Gate::Auth.new(@container).check_action!(action: :converge, actor: @call.role, key: key)
        envelope = Envelope::Writer.from(container: @container, call: @call).put(
          key,
          mentry: ctx.entry,
          payload: Envelope::Writer::Payload.new(**normalized),
        )
        Produce::Render.new(@container).render_if_configured(key, ctx.entry, envelope)
        envelope
      end

      def normalize(data, format)
        return { meta: {}, body: "", content: nil } if data.nil?

        data = data.transform_keys(&:to_s) if data.is_a?(Hash)
        case format.to_s
        when "markdown", "text"
          { meta: data["_meta"] || {}, body: (data["body"] || "").to_s, content: nil }
        when "json", "yaml"
          { meta: data["_meta"] || {}, body: nil, content: data["content"] || data }
        else
          { meta: {}, body: data.to_s, content: nil }
        end
      end
    end
  end
end
