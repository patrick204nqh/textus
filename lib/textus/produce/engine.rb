module Textus
  module Produce
    class Engine
      def self.converge(container:, call:, keys:)
        Textus::Ports::BuildLock.with(root: container.root) do
          new(container: container, call: call).call(keys: keys)
        end
      rescue Textus::BuildInProgress
        nil
      rescue Textus::Error => e
        container.steps.publish(
          :produce_failed,
          ctx: Textus::Step::Context.for(container: container, call: call),
          keys: keys, error: e.message
        )
      end

      def initialize(container:, call:)
        @container = container
        @call      = call
        @manifest  = container.manifest
      end

      def call(keys:)
        build_call = build_actor_call
        context    = build_context(build_call)
        out = { produced: [], skipped: [], failed: [] }

        keys.each do |key|
          produce_one(key, build_call, context, out)
        rescue Textus::Error => e
          out[:failed] << { "key" => key, "error" => e.message }
        end
        out
      end

      private

      def produce_one(key, build_call, context, out)
        entry = @manifest.resolver.resolve(key).entry

        if entry.intake?
          Textus::Pipeline::Acquire::Intake.new(container: @container, call: build_call).run(key)
          entry.publish_via(context)
          out[:produced] << key
        else
          result = entry.publish_via(context)
          result.nil? ? (out[:skipped] << key) : (out[:produced] << key)
        end
      end

      def build_actor_call
        build_role = @manifest.policy.actor_for("converge") or
          raise Textus::UsageError.new(
            "no role holds the 'converge' capability",
            hint: "declare a role with `can: [converge]` in .textus/manifest.yaml",
          )
        Textus::Call.build(
          role: build_role,
          correlation_id: @call.correlation_id,
          dry_run: @call.dry_run,
        )
      end

      def build_context(call)
        Textus::Manifest::Entry::Base::PublishContext.new(
          container: @container, call: call,
          reader: lambda { |key|
            Textus::Action::Get.new(key: key).call(container: @container, call: call)
          }
        )
      end
    end
  end
end
