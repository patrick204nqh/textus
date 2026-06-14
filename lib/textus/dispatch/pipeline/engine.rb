module Textus
  module Dispatch
    module Pipeline
      # The single convergence engine (ADR 0093/0094). "Make these machine entries
      # current from upstream." Acquire is per-`from`; publish is one uniform
      # `publish_via` entry point for all kinds (ADR 0094):
      #   intake  (from: handler)  -> re-pull (Produce::Acquire::Intake), then publish_via
      #   derived (from: project)  -> build data + publish_via (ToPaths or None)
      #   derived (from: command)  -> skip the build; publish_via publishes
      #                               existing store bytes via mode resolution
      #                               (None when no targets -> skipped)
      # Runs as the converge build actor (self-elevating); the passed `call`
      # supplies only correlation_id/dry_run. Callers choose the key set: the
      # write subscriber passes rdeps ∩ derived; the converge pass passes
      # all-derived + stale-intake.
      class Engine
        # Locked + failure-isolated convergence — the entry point worker handlers
        # call to materialize a key set (ADR 0093 / job-queue model). A held lock
        # is a soft miss (an in-flight build/converge already produces fresh
        # output); any other error is republished as :produce_failed and never
        # raised at the caller (ADR 0087 §5 failure isolation, preserved).
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

        # keys: the machine entry keys to converge. Returns
        #   { produced: [k...], skipped: [k...], failed: [{ "key"=>, "error"=> }...] }
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

        # Acquire is per-`from`; publish is one uniform entry point (publish_via)
        # for every kind. The command emit-vs-skip falls out of publish-mode
        # resolution (Publish::None when no targets), so there is no command branch.
        def produce_one(key, build_call, context, out)
          entry = @manifest.resolver.resolve(key).entry

          if entry.intake?
            Textus::Dispatch::Pipeline::Acquire::Intake.new(container: @container, call: build_call).run(key) # acquire: re-pull
            entry.publish_via(context)                                                # emit any targets
            out[:produced] << key                                                     # a fetch is production
          else
            result = entry.publish_via(context) # derived builds inside; command publishes-or-None
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
end
