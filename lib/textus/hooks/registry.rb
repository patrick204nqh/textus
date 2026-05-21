module Textus
  module Hooks
    class Registry
      EVENTS = {
        # RPC: exactly 1 handler per name; return value flows into store; failure aborts.
        fetch: { mode: :rpc, args: %i[store config args] },
        reduce: { mode: :rpc, args: %i[store rows config] },
        check: { mode: :rpc, args: %i[store] },

        # Pub-sub: 0..N handlers per event; return discarded; failure logged to audit.
        put: { mode: :pubsub, args: %i[store key envelope] },
        delete: { mode: :pubsub, args: %i[store key] },
        refresh: { mode: :pubsub, args: %i[store key envelope change] },
        build: { mode: :pubsub, args: %i[store key envelope sources] },
        accept: { mode: :pubsub, args: %i[store key target_key] },
        publish: { mode: :pubsub, args: %i[store key envelope source target] },
        mv: { mode: :pubsub, args: %i[store key from_key to_key envelope] },
      }.freeze

      def initialize(dispatcher: nil)
        @rpc        = Hash.new { |h, k| h[k] = {} }   # event => { name => callable }
        @pubsub     = Hash.new { |h, k| h[k] = [] }   # event => [{name:, callable:, keys:}]
        @dispatcher = dispatcher
      end

      def register(event, name, keys: nil, &blk)
        spec = EVENTS[event.to_sym] or raise UsageError.new("unknown event: #{event}")
        shape_check!(event, spec, blk)
        name = name.to_sym

        case spec[:mode]
        when :rpc
          raise UsageError.new("#{event} '#{name}' already registered") if @rpc[event.to_sym].key?(name)

          @rpc[event.to_sym][name] = blk
        when :pubsub
          raise UsageError.new("#{event} hook '#{name}' already registered") if @pubsub[event.to_sym].any? { |h| h[:name] == name }

          @pubsub[event.to_sym] << { name: name, callable: blk, keys: keys }
          @dispatcher&.subscribe(event, name, keys: keys, &blk)
        end
      end

      def rpc_callable(event, name)
        @rpc[event.to_sym][name.to_sym] or
          raise UsageError.new("unknown #{event}: #{name}")
      end

      def listeners(event, key:)
        @pubsub[event.to_sym].select { |h| h[:keys].nil? || matches_any?(h[:keys], key) }
      end

      def rpc_names(event) = @rpc[event.to_sym].keys
      def pubsub_handlers(event) = @pubsub[event.to_sym]

      private

      def shape_check!(event, spec, blk)
        required = spec[:args]
        provided = blk.parameters.select { |t, _| %i[keyreq key keyrest].include?(t) } # rubocop:disable Style/HashSlice
        keyrest  = provided.any? { |t, _| t == :keyrest }
        missing  = required - provided.map { |_, n| n }
        return if keyrest || missing.empty?

        raise UsageError.new(
          "#{event} hooks must accept kwargs: #{required.join(", ")} (missing: #{missing.join(", ")})",
        )
      end

      def matches_any?(globs, key)
        Array(globs).any? { |g| File.fnmatch?(g, key.to_s, File::FNM_PATHNAME) }
      end
    end
  end
end
