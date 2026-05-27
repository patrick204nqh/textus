# frozen_string_literal: true

module Textus
  module Hooks
    class Bus
      HOOK_TIMEOUT_SECONDS = 2

      class HookTimeout < StandardError; end

      EVENTS = {
        resolve_intake: { mode: :rpc, args: %i[store config args] },
        transform_rows: { mode: :rpc, args: %i[store rows config] },
        validate: { mode: :rpc, args: %i[store] },

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

      def initialize
        @rpc    = Hash.new { |h, k| h[k] = {} }
        @pubsub = Hash.new { |h, k| h[k] = [] }
        @error_handlers = []
      end

      def on(event, name, keys: nil, &) = register(event, name, keys: keys, &)

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
        end
      end

      def on_error(&block) = @error_handlers << block

      def rpc_callable(event, name)
        @rpc[event.to_sym][name.to_sym] or raise UsageError.new("unknown #{event}: #{name}")
      end

      def rpc_names(event)        = @rpc[event.to_sym].keys
      def pubsub_handlers(event)  = @pubsub[event.to_sym]
      def listeners(event, key:)  = @pubsub[event.to_sym].select { |h| h[:keys].nil? || matches_any?(h[:keys], key) }

      def publish(event, strict: false, **kwargs)
        key = kwargs[:key] || "-"
        fired = []
        errored = []
        timed_out = []
        raised = nil

        @pubsub[event.to_sym].each do |sub|
          next unless match?(sub[:keys], key)

          outcome, err = invoke(event, sub, key, kwargs)
          case outcome
          when :ok        then fired << sub[:name]
          when :errored   then errored << sub[:name]
          when :timed_out then timed_out << sub[:name]
          end
          raised ||= err if strict && err
        end

        raise raised if strict && raised

        FireReport.new(fired: fired, errored: errored, timed_out: timed_out)
      end

      private

      def invoke(event, sub, key, kwargs)
        accepted = filter_kwargs(sub[:callable], kwargs)
        error = nil

        thread = Thread.new do
          sub[:callable].call(**accepted)
        rescue StandardError => e
          error = e
        end

        if thread.join(HOOK_TIMEOUT_SECONDS).nil?
          thread.kill
          err = HookTimeout.new("hook #{sub[:name]} exceeded #{HOOK_TIMEOUT_SECONDS}s on event #{event}")
          notify_error(event, sub, key, kwargs, err)
          return [:timed_out, err]
        end

        if error
          notify_error(event, sub, key, kwargs, error)
          return [:errored, error]
        end

        [:ok, nil]
      end

      def notify_error(event, sub, key, kwargs, error)
        @error_handlers.each do |handler|
          handler.call(event: event, hook: sub[:name], key: key, kwargs: kwargs, error: error)
        rescue StandardError => e
          warn "[textus] error handler failed: #{e.class}: #{e.message}"
        end
      end

      def filter_kwargs(callable, kwargs)
        params = callable.parameters
        return kwargs if params.any? { |type, _| type == :keyrest }

        accepted = params.each_with_object([]) do |(type, name), acc|
          acc << name if %i[key keyreq].include?(type)
        end
        kwargs.slice(*accepted)
      end

      def shape_check!(event, spec, blk)
        required = spec[:args]
        provided = blk.parameters.select { |t, _| %i[keyreq key keyrest].include?(t) } # rubocop:disable Style/HashSlice
        keyrest  = provided.any? { |t, _| t == :keyrest }
        missing  = required - provided.map { |_, n| n }
        return if keyrest || missing.empty?

        raise UsageError.new("#{event} hooks must accept kwargs: #{required.join(", ")} (missing: #{missing.join(", ")})")
      end

      def match?(globs, key)
        return true if globs.nil?

        Array(globs).any? { |g| File.fnmatch?(g, key.to_s, File::FNM_PATHNAME) }
      end

      def matches_any?(globs, key) = match?(globs, key)
    end
  end
end
