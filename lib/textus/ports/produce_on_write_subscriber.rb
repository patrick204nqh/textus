# frozen_string_literal: true

module Textus
  module Ports
    # ADR 0093: on a canon write, converge the derived entries that depend on the
    # written key (rdeps ∩ derived) by running Produce — scoped + non-destructive.
    # This IS reconcile narrowed to a write's blast radius; there is no separate
    # "reactive materialize" subsystem. Per-entry source.on_write (sync|async)
    # picks inline-under-lock vs deferred. A write INTO a derived entry does not
    # fan out (recursion guard). Failures never reach the writer (Produce.converge
    # isolates them). Attached at Store boot, alongside AuditSubscriber.
    class ProduceOnWriteSubscriber
      def initialize(container)
        @container = container
      end

      def attach(bus)
        bus.on(:entry_put, :produce_on_write) do |ctx:, key:, **|
          call = Textus::Call.build(role: ctx.role, correlation_id: ctx.correlation_id)
          on_write(key: key, call: call)
        end
        self
      end

      def on_write(key:, call:)
        return if derived_write?(key) # recursion guard: produce output is not a source change

        affected = Textus::Read::Rdeps.new(container: @container).call(key)["rdeps"]
        producible = affected.select { |k| producible?(k) }
        return if producible.empty?

        if any_sync?(producible)
          Textus::Maintenance::Produce.converge(container: @container, call: call, keys: producible)
        else
          Textus::Maintenance::Produce::AsyncRunner.enqueue(container: @container, call: call, keys: producible)
        end
      end

      private

      def derived_write?(key)
        @container.manifest.resolver.resolve(key).entry.derived?
      rescue Textus::Error
        false
      end

      # The producible scope mirrors Maintenance::Produce#produce_one: derived
      # entries render+publish, and nested publish_tree entries mirror their
      # source subtree (ADR 0047). Including the latter restores reactive
      # re-mirroring on a write into a tree's source — dropped when the scope
      # narrowed to `derived?` only.
      def producible?(key)
        entry = @container.manifest.resolver.resolve(key).entry
        entry.derived? || !entry.publish_tree.nil?
      rescue Textus::Error
        false
      end

      # Only derived entries carry a source with on_write semantics; a nested
      # publish_tree entry has no source and defaults to async.
      def any_sync?(keys)
        keys.any? do |k|
          entry = @container.manifest.resolver.resolve(k).entry
          entry.derived? && entry.source.sync?
        end
      end
    end
  end
end
