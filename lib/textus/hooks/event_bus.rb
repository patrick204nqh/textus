# frozen_string_literal: true

module Textus
  module Hooks
    class EventBus
      HOOK_TIMEOUT_SECONDS = 2

      class HookTimeout < StandardError; end

      def initialize(error_log: ErrorLog.new)
        @pubsub = Hash.new { |h, k| h[k] = [] }
        @error_handlers = []
        @error_log = error_log
      end

      attr_reader :error_log

      def on(event, name, keys: nil, &) = register(event, name, keys: keys, &)

      def register(event, name, keys: nil, &blk)
        event_sym = event.to_sym
        raise UsageError.new("#{event_sym} is an RPC event; register on RpcRegistry") if Catalog::RPC.key?(event_sym)

        required = Catalog::PUBSUB[event_sym] or raise UsageError.new("unknown event: #{event}")
        sig = Signature.new(blk)
        missing = sig.missing(required)
        if missing.any?
          raise UsageError.new("#{event_sym} hooks must accept kwargs: #{required.join(", ")} (missing: #{missing.join(", ")})")
        end

        name = name.to_sym
        raise UsageError.new("#{event_sym} hook '#{name}' already registered") if @pubsub[event_sym].any? { |h| h[:name] == name }

        @pubsub[event_sym] << { name: name, callable: blk, keys: keys }
      end

      def on_error(&block) = @error_handlers << block

      def listeners(event, key:) = @pubsub[event.to_sym].select { |h| match?(h[:keys], key) }

      def pubsub_handlers(event) = @pubsub[event.to_sym]

      def pubsub_handlers_names = @pubsub.values.flatten.map { |h| h[:name] }

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
        accepted = Signature.new(sub[:callable]).filter(kwargs)
        error = nil
        # Thread#kill is unsafe in general but bounded here: post-commit, isolated, only a runaway user hook is affected.
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

      def match?(globs, key)
        return true if globs.nil?

        Array(globs).any? { |g| File.fnmatch?(g, key.to_s, File::FNM_PATHNAME) }
      end
    end
  end
end
