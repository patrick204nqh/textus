module Textus
  module Hooks
    class Registry
      EVENTS = {
        # RPC: exactly 1 handler per name; return value flows into store; failure aborts.
        resolve_intake: { mode: :rpc, args: %i[store config args] },
        transform_rows: { mode: :rpc, args: %i[store rows config] },
        validate: { mode: :rpc, args: %i[store] },

        # Pub-sub: 0..N handlers per event; return discarded; failure logged to audit.
        entry_put: { mode: :pubsub, args: %i[store key envelope] },
        entry_deleted: { mode: :pubsub, args: %i[store key] },
        entry_refreshed: { mode: :pubsub, args: %i[store key envelope change] },
        entry_renamed: { mode: :pubsub, args: %i[store key from_key to_key envelope] },
        build_completed: { mode: :pubsub, args: %i[store key envelope sources] },
        proposal_accepted: { mode: :pubsub, args: %i[store key target_key] },
        proposal_rejected: { mode: :pubsub, args: %i[store key target_key] },
        file_published: { mode: :pubsub, args: %i[store key envelope source target] },
        store_loaded: { mode: :pubsub, args: %i[store] },
        refresh_started: { mode: :pubsub, args: %i[store key mode] },
        refresh_failed: { mode: :pubsub, args: %i[store key error_class error_message] },
        refresh_backgrounded: { mode: :pubsub, args: %i[store key started_at budget_ms] },
      }.freeze

      def initialize(dispatcher: nil)
        @rpc        = Hash.new { |h, k| h[k] = {} }   # event => { name => callable }
        @pubsub     = Hash.new { |h, k| h[k] = [] }   # event => [{name:, callable:, keys:}]
        @dispatcher = dispatcher
      end

      def on(event, name, keys: nil, &)
        register(event, name, keys: keys, &)
      end

      def register(event, name, keys: nil, &blk)
        event_sym = event.to_sym
        spec = EVENTS[event_sym] or raise UsageError.new("unknown event: #{event}")
        shape_check!(event_sym, spec, blk)
        name = name.to_sym

        case spec[:mode]
        when :rpc
          raise UsageError.new("#{event_sym} '#{name}' already registered") if @rpc[event_sym].key?(name)

          @rpc[event_sym][name] = blk
        when :pubsub
          raise UsageError.new("#{event_sym} hook '#{name}' already registered") if @pubsub[event_sym].any? { |h| h[:name] == name }

          @pubsub[event_sym] << { name: name, callable: blk, keys: keys }
          @dispatcher&.subscribe(event_sym, name, keys: keys, &blk)
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
