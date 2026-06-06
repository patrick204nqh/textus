module Textus
  module Maintenance
    # The single convergence engine (ADR 0093). "Make these machine entries
    # current from upstream." Dispatches per entry kind:
    #   intake  (handler)             -> re-pull (FetchWorker)
    #   derived (template/projection) -> render + publish (publish_via)
    #   derived (command/external)    -> skip (no in-process runner; staleness only)
    # Runs as the reconcile build actor (self-elevating); the passed `call`
    # supplies only correlation_id/dry_run. Callers choose the key set: the
    # write subscriber passes rdeps ∩ derived; reconcile passes
    # all-derived + stale-intake.
    class Produce
      # Locked + failure-isolated convergence — the shared entry point for the
      # write trigger (ADR 0093). Both the sync path (inline, in the subscriber)
      # and the async path (AsyncRunner) call this. A held lock is a soft miss
      # (an in-flight build/reconcile already produces fresh output); any other
      # error is republished as :materialize_failed and never raised at the
      # writer (ADR 0087 §5 failure isolation, preserved).
      def self.converge(container:, call:, keys:)
        Textus::Ports::BuildLock.with(root: container.root) do
          new(container: container, call: call).call(keys: keys)
        end
      rescue Textus::BuildInProgress
        nil
      rescue Textus::Error => e
        container.events.publish(
          :materialize_failed,
          ctx: Textus::Hooks::Context.for(container: container, call: call),
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

      def produce_one(key, build_call, context, out)
        entry = @manifest.resolver.resolve(key).entry
        if entry.intake?
          Write::FetchWorker.new(container: @container, call: build_call).run(key)
          out[:produced] << key
        elsif entry.derived?
          result = entry.publish_via(context)
          result.nil? ? (out[:skipped] << key) : (out[:produced] << key)
        else
          out[:skipped] << key # non-machine entry: nothing to produce
        end
      end

      def build_actor_call
        build_role = @manifest.policy.actor_for("reconcile") or
          raise Textus::UsageError.new(
            "no role holds the 'reconcile' capability",
            hint: "declare a role with `can: [reconcile]` in .textus/manifest.yaml",
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
          reader: Textus::Read::Get.new(container: @container, call: call)
        )
      end

      # In-process deferral for the async write trigger (ADR 0087/0093).
      # Spawns a tracked thread that runs Produce.converge after the write
      # returns; a one-time at_exit joins
      # all pending threads so a short-lived CLI process cannot exit before an
      # async rebuild completes. The write itself never blocks.
      module AsyncRunner
        @mutex   = Mutex.new
        @threads = []
        @hooked  = false

        class << self
          def enqueue(container:, call:, keys:)
            thread = Thread.new { Produce.converge(container: container, call: call, keys: keys) }
            track(thread)
            thread
          end

          # Block until every spawned async rebuild has finished. Idempotent;
          # safe to call from at_exit and directly from tests.
          def drain
            pending = @mutex.synchronize { @threads.dup }
            pending.each(&:join)
            @mutex.synchronize { @threads.delete_if { |t| !t.alive? } }
            nil
          end

          private

          def track(thread)
            @mutex.synchronize do
              @threads.delete_if { |t| !t.alive? }
              @threads << thread
              install_drain_hook
            end
          end

          # Register the join-before-exit hook exactly once. Guarded by the
          # caller holding @mutex.
          def install_drain_hook
            return if @hooked

            @hooked = true
            at_exit { drain }
          end
        end
      end
    end
  end
end
