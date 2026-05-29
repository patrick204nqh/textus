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
        shape_check!(event_sym, required, blk)
        name = name.to_sym
        raise UsageError.new("#{event_sym} '#{name}' already registered") if @table[event_sym].key?(name)

        @table[event_sym][name] = blk
      end

      def names(event) = @table[event.to_sym].keys

      def callable(event, name)
        @table[event.to_sym][name.to_sym] or raise UsageError.new("unknown #{event}: #{name}")
      end

      # Invoke a registered callable, injecting `caps:` under the kwarg name
      # the callable declares. Legacy `store:` is rejected (no shim).
      def invoke(event, name, caps:, **other)
        blk = callable(event, name)
        params = blk.parameters
        accepts_keyrest = params.any? { |t, _| t == :keyrest }
        declared = params.each_with_object([]) { |(t, n), acc| acc << n if %i[key keyreq].include?(t) }

        if declared.include?(:store)
          raise UsageError.new(
            "RPC callable for #{event} '#{name}' declares legacy `store:`; rename to `caps:` " \
            "(Textus::Container)",
          )
        end

        kwargs = other.dup
        kwargs[:caps] = caps if accepts_keyrest || declared.include?(:caps)
        blk.call(**kwargs)
      end

      private

      def shape_check!(event, required, blk)
        provided = blk.parameters.select { |t, _| %i[keyreq key keyrest].include?(t) } # rubocop:disable Style/HashSlice
        return if provided.any? { |t, _| t == :keyrest }

        param_names = provided.map { |_, n| n }
        # Allow `store:` as a stand-in for `caps:` so registration succeeds;
        # invoke will raise UsageError when the callable is actually called.
        effective_required = if param_names.include?(:store)
                               required.map { |r| r == :caps ? :store : r }
                             else
                               required
                             end
        missing = effective_required - param_names
        return if missing.empty?

        raise UsageError.new("#{event} RPC must accept kwargs: #{required.join(", ")} (missing: #{missing.join(", ")})")
      end
    end
  end
end
