# frozen_string_literal: true

module Textus
  module Step
    # The single home for registered steps. Reuses Hooks::EventBus for observe
    # (pub/sub) dispatch — including its timeout isolation and error ring buffer
    # — and holds a kind->{name->instance} table for the invocable kinds
    # (fetch/transform/validate). Replaces the EventBus+RpcRegistry pair.
    class Registry
      def initialize(error_log: Hooks::ErrorLog.new)
        @bus   = Hooks::EventBus.new(error_log: error_log)
        @table = Hash.new { |h, k| h[k] = {} }
      end

      # Register a Step instance. Observe steps go to the bus; the rest go to
      # the invocable table keyed by (kind, name).
      def register(step)
        kind = step.class.kind
        name = step.name.to_sym
        return register_observe(step) if kind == :observe

        raise UsageError.new("#{kind} '#{name}' already registered") if @table[kind].key?(name)

        @table[kind][name] = step
      end

      # Invoke an invocable step. Mirrors the old RpcRegistry#invoke: inject
      # caps only when #call declares :caps or accepts keyrest.
      def invoke(kind, name, caps:, **other)
        step = @table[kind][name.to_sym] or raise UsageError.new("unknown #{kind}: #{name}")
        sig = Hooks::Signature.new(step.method(:call))
        kwargs = other.dup
        kwargs[:caps] = caps if sig.accepts_keyrest? || sig.declared_keys.include?(:caps)
        step.call(**kwargs)
      end

      def names(kind)
        return @bus.pubsub_handlers_names if kind.to_sym == :observe

        @table[kind.to_sym].keys
      end

      # Pub/sub passthrough (observe + internal built-in subscribers).
      def publish(event, **) = @bus.publish(event, **)
      def on(event, name, keys: nil, &) = @bus.register(event, name, keys: keys, &)
      def on_error(&) = @bus.on_error(&)
      def error_log = @bus.error_log

      private

      def register_observe(step)
        sig = Hooks::Signature.new(step.method(:call))
        @bus.register(step.class.event, step.name, keys: step.class.match) do |**kw|
          step.call(**sig.filter(kw))
        end
      end
    end
  end
end
