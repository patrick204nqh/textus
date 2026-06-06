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
        derived = affected.select { |k| derived_write?(k) }
        return if derived.empty?

        if any_sync?(derived)
          Textus::Maintenance::Produce.converge(container: @container, call: call, keys: derived)
        else
          Textus::Maintenance::Produce::AsyncRunner.enqueue(container: @container, call: call, keys: derived)
        end
      end

      private

      def derived_write?(key)
        @container.manifest.resolver.resolve(key).entry.derived?
      rescue Textus::Error
        false
      end

      def any_sync?(keys)
        keys.any? { |k| @container.manifest.resolver.resolve(k).entry.source.sync? }
      end
    end
  end
end
