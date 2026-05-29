# frozen_string_literal: true

module Textus
  module Hooks
    class RpcRegistry
      EVENTS = {
        resolve_intake: %i[caps config args],
        transform_rows: %i[caps rows config],
        validate: %i[caps],
      }.freeze

      PUBSUB_EVENTS = EventBus::EVENTS.keys.freeze

      def initialize
        @table = Hash.new { |h, k| h[k] = {} }
      end

      def register(event, name, &blk)
        event_sym = event.to_sym
        raise UsageError.new("#{event_sym} is a pubsub event; register on EventBus") if PUBSUB_EVENTS.include?(event_sym)

        required = EVENTS[event_sym] or raise UsageError.new("unknown RPC event: #{event}")
        sig = Signature.new(blk)
        missing = sig.missing(required)
        raise UsageError.new("#{event_sym} RPC must accept kwargs: #{required.join(", ")} (missing: #{missing.join(", ")})") if missing.any?

        name = name.to_sym
        raise UsageError.new("#{event_sym} '#{name}' already registered") if @table[event_sym].key?(name)

        @table[event_sym][name] = blk
      end

      def names(event) = @table[event.to_sym].keys

      def callable(event, name)
        @table[event.to_sym][name.to_sym] or raise UsageError.new("unknown #{event}: #{name}")
      end

      # Invoke a registered callable, injecting `caps:` only if the callable
      # declares it (or accepts keyrest). Mis-named kwargs (e.g. the legacy
      # `caps:`-alternative) are rejected at registration time, not here.
      def invoke(event, name, caps:, **other)
        blk = callable(event, name)
        sig = Signature.new(blk)
        kwargs = other.dup
        kwargs[:caps] = caps if sig.accepts_keyrest? || sig.declared_keys.include?(:caps)
        blk.call(**kwargs)
      end
    end
  end
end
