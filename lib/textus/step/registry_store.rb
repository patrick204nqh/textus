# frozen_string_literal: true

module Textus
  module Step
    # The single home for registered steps. Reuses Step::EventBus for observe
    # (pub/sub) dispatch — including its timeout isolation and error ring buffer
    # — and holds a kind->{name->instance} table for the invocable kinds
    # (fetch/transform/validate). Replaces the EventBus+RpcRegistryStore pair.
    class RegistryStore
      def initialize(error_log: Step::ErrorLog.new)
        @bus   = Step::EventBus.new(error_log: error_log)
        @table = Hash.new { |h, k| h[k] = {} }
      end

      # Register either a Step instance (invocable/observe table) or a pub/sub
      # subscriber (`register(event, name, keys:, &block)`) for internal/spec
      # probes.
      def register(step, *, keys: nil, &)
        return @bus.register(step, *, keys: keys, &) unless step.is_a?(Step::Base)

        kind = step.class.kind
        name = step.name.to_sym
        return register_observe(step) if kind == :observe

        raise UsageError.new("#{kind} '#{name}' already registered") if @table[kind].key?(name)

        @table[kind][name] = step
      end

      # Invoke an invocable step. Mirrors the old RpcRegistryStore#invoke: inject
      # caps only when #call declares :caps or accepts keyrest.
      def invoke(kind, name, caps:, **other)
        step = @table[kind][name.to_sym] or raise UsageError.new("unknown #{kind}: #{name}")
        sig = Step::Signature.new(step.method(:call))
        kwargs = other.dup
        kwargs[:caps] = caps if sig.accepts_keyrest? || sig.declared_keys.include?(:caps)
        step.call(**kwargs)
      end

      def names(kind)
        return @bus.pubsub_handlers_names if kind.to_sym == :observe

        @table[kind.to_sym].keys
      end

      def pubsub_handlers(event)
        @bus.pubsub_handlers(event)
      end

      # Pub/sub passthrough (observe + internal built-in subscribers).
      def publish(event, **) = @bus.publish(event, **)
      def on(event, name, keys: nil, &) = @bus.register(event, name, keys: keys, &)
      def on_error(&) = @bus.on_error(&)
      def error_log = @bus.error_log

      private

      def register_observe(step)
        sig = Step::Signature.new(step.method(:call))
        @bus.register(step.class.event, step.name, keys: step.class.match) do |**kw|
          step.call(**sig.filter(kw))
        end
      end
    end
  end
end
