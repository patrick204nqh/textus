module Textus
  module Maintenance
    # Reactive half of ADR 0087: on a canon write, re-materialize the derived
    # entries that depend on the written key (rdeps ∩ derived). Per-entry
    # `materialize: { on_change }` selects sync (inline, under the maintenance
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

      # Sync iff ANY affected entry's materialize rule resolves on_change: sync.
      def any_sync?(keys)
        keys.any? { |k| @manifest.rules.for(k).materialize&.sync? }
      end

      def publish_failed(keys, call, error)
        @container.events.publish(
          :materialize_failed,
          ctx: Textus::Hooks::Context.for(container: @container, call: call),
          keys: keys,
          error: error.message,
        )
      end

      # Async runner: an in-process, fire-and-forget thread that runs the
      # materialization after the write returns, under the same maintenance
      # lock. textus schedules nothing itself; this is the deferral mechanism.
      # Failure isolation is inherited from #materialize.
      module AsyncRunner
        def self.enqueue(container:, call:, keys:)
          Thread.new do
            ReactiveMaterialize.new(container: container).materialize(keys, call)
          end
        end
      end
    end
  end
end
