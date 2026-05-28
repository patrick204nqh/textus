# frozen_string_literal: true

module Textus
  module Hooks
    class EventBus
      HOOK_TIMEOUT_SECONDS = 2

      class HookTimeout < StandardError; end

      EVENTS = {
        entry_put: %i[ctx key envelope],
        entry_deleted: %i[ctx key],
        entry_refreshed: %i[ctx key envelope change],
        entry_renamed: %i[ctx key from_key to_key envelope],
        build_completed: %i[ctx key envelope sources],
        proposal_accepted: %i[ctx key target_key],
        proposal_rejected: %i[ctx key target_key],
        file_published: %i[ctx key envelope source target],
        store_loaded: %i[ctx],
        refresh_started: %i[ctx key mode],
        refresh_failed: %i[ctx key error_class error_message],
        refresh_backgrounded: %i[ctx key started_at budget_ms],
      }.freeze

      RPC_EVENTS = %i[resolve_intake transform_rows validate].freeze

      def initialize(error_log: ErrorLog.new)
        @pubsub = Hash.new { |h, k| h[k] = [] }
        @error_handlers = []
        @error_log = error_log
      end

      attr_reader :error_log

      def on(event, name, keys: nil, &) = register(event, name, keys: keys, &)

      def register(event, name, keys: nil, &blk)
        event_sym = event.to_sym
        raise UsageError.new("#{event_sym} is an RPC event; register on RpcRegistry") if RPC_EVENTS.include?(event_sym)

        required = EVENTS[event_sym] or raise UsageError.new("unknown event: #{event}")
        shape_check!(event_sym, required, blk)
        name = name.to_sym
        raise UsageError.new("#{event_sym} hook '#{name}' already registered") if @pubsub[event_sym].any? { |h| h[:name] == name }

        @pubsub[event_sym] << { name: name, callable: blk, keys: keys }
      end

      def on_error(&block) = @error_handlers << block

      def listeners(event, key:) = @pubsub[event.to_sym].select { |h| match?(h[:keys], key) }

      def pubsub_handlers(event) = @pubsub[event.to_sym]

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
        @error_log.record(
          seq: kwargs[:_audit_seq] || -1,
          event: event,
          hook: sub[:name],
          key: key,
          error_class: error.class.name,
          error_message: error.message,
        )
        @error_handlers.each do |handler|
          handler.call(event: event, hook: sub[:name], key: key, kwargs: kwargs, error: error)
        rescue StandardError => e
          warn "[textus] error handler failed: #{e.class}: #{e.message}"
        end
      end

      def filter_kwargs(callable, kwargs)
        params = callable.parameters
        return kwargs if params.any? { |type, _| type == :keyrest }

        accepted = params.each_with_object([]) { |(t, n), acc| acc << n if %i[key keyreq].include?(t) }
        kwargs.slice(*accepted)
      end

      def shape_check!(event, required, blk)
        provided = blk.parameters.select { |t, _| %i[keyreq key keyrest].include?(t) } # rubocop:disable Style/HashSlice
        return if provided.any? { |t, _| t == :keyrest }

        missing = required - provided.map { |_, n| n }
        return if missing.empty?

        raise UsageError.new("#{event} hooks must accept kwargs: #{required.join(", ")} (missing: #{missing.join(", ")})")
      end

      def match?(globs, key)
        return true if globs.nil?

        Array(globs).any? { |g| File.fnmatch?(g, key.to_s, File::FNM_PATHNAME) }
      end
    end
  end
end
