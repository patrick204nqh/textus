module Textus
  module Maintenance
    # Reactive half of ADR 0087: on a canon write, re-materialize the derived
    # entries that depend on the written key (rdeps ∩ derived). Per-entry
    # `upkeep: { "on": source_change, strategy }` selects sync (inline, under the maintenance
    # lock) vs async (deferred, the default). Writes into derived-zone entries do
    # not fan out (recursion guard). Failures never propagate to the writer
    # (ADR 0087 §5): a soft miss on the lock is swallowed, and a materialization
    # error is rescued and republished as :materialize_failed.
    class ReactiveMaterialize
      def initialize(container:)
        @container = container
        @manifest  = container.manifest
      end

      # key:  the just-written canon key.
      # call: the originating Call (role/correlation_id/dry_run).
      def on_write(key:, call:)
        return if derived_zone?(key) # recursion guard

        affected = Textus::Read::Rdeps.new(container: @container).call(key)["rdeps"]
        return if affected.empty?

        if any_sync?(affected)
          materialize(affected, call) # inline, blocking, under lock
        else
          AsyncRunner.enqueue(container: @container, call: call, keys: affected)
        end
      end

      # Acquire the shared maintenance lock and materialize the impact set.
      # Failure isolation per ADR 0087 §5: a held lock is a soft miss (an
      # in-flight build/reconcile already produces fresh output), and any other
      # Textus::Error is republished as :materialize_failed. Never raises.
      # Also the body of the async deferral (AsyncRunner runs it off-thread).
      def materialize(keys, call)
        Textus::Ports::BuildLock.with(root: @container.root) do
          Textus::Maintenance::Materialize.new(container: @container, call: call).call(keys: keys)
        end
      rescue Textus::BuildInProgress
        nil # soft miss — the in-flight holder will produce fresh output
      rescue Textus::Error => e
        publish_failed(keys, call, e)
      end

      private

      # The recursion guard: a write into a derived-kind zone is materialization
      # output, not a source change, so it must not fan out (it would loop).
      def derived_zone?(key)
        zone = @manifest.resolver.resolve(key).entry.zone
        @manifest.policy.derived_zone?(zone)
      rescue Textus::Error
        false # unknown key → let the rdeps step decide (it returns empty)
      end

      # Sync iff ANY affected entry's upkeep (on: source_change) rule resolves strategy: sync.
      def any_sync?(keys)
        keys.any? { |k| @manifest.rules.for(k).upkeep&.materialize&.sync? }
      end

      def publish_failed(keys, call, error)
        @container.events.publish(
          :materialize_failed,
          ctx: Textus::Hooks::Context.for(container: @container, call: call),
          keys: keys,
          error: error.message,
        )
      end

      # Async runner: an in-process deferral that runs the materialization after
      # the write returns, under the same maintenance lock. textus schedules
      # nothing itself; this is the deferral mechanism. Failure isolation is
      # inherited from #materialize.
      #
      # Completion guarantee (ADR 0087): a bare detached Thread is unreliable in
      # a short-lived CLI process — the interpreter can exit and reap the thread
      # before it finishes, silently dropping the rebuild. So every spawned
      # thread is tracked, and a one-time `at_exit` joins all pending threads
      # before the process exits. The write itself is never blocked (enqueue
      # returns the instant the thread is spawned); only process *exit* waits,
      # which is exactly when a CLI verb has already produced its response. In
      # the long-lived MCP server the threads simply complete on their own and
      # the drain is a no-op at shutdown.
      module AsyncRunner
        @mutex   = Mutex.new
        @threads = []
        @hooked  = false

        class << self
          def enqueue(container:, call:, keys:)
            thread = Thread.new do
              ReactiveMaterialize.new(container: container).materialize(keys, call)
            end
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
