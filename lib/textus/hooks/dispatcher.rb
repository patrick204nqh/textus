# frozen_string_literal: true

module Textus
  module Hooks
    class Dispatcher
      HOOK_TIMEOUT_SECONDS = 2

      # Raised on the worker thread when a hook exceeds HOOK_TIMEOUT_SECONDS.
      # Surfaces to on_error callbacks (so audit rows still get written) and
      # is recorded in FireReport#timed_out.
      class HookTimeout < StandardError; end

      def initialize
        @subscribers = Hash.new { |h, k| h[k] = [] }
        @error_handlers = []
      end

      # Register an error callback invoked when a user hook raises or times
      # out. Used by Infra::AuditSubscriber to record an "event_error" audit
      # row.
      def on_error(&block)
        @error_handlers << block
      end

      def subscribe(event, name, keys: nil, &block)
        @subscribers[event.to_sym] << { name: name.to_sym, callable: block, keys: keys }
      end

      # Fires every subscriber whose key-glob matches and returns a FireReport.
      # When strict: true, raises the first failure encountered (in subscriber
      # iteration order) after every hook has been attempted.
      def publish(event, strict: false, **kwargs)
        key = kwargs[:key] || "-"
        fired = []
        errored = []
        timed_out = []
        raised = nil

        @subscribers[event.to_sym].each do |sub|
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
          err = HookTimeout.new(
            "hook #{sub[:name]} exceeded #{HOOK_TIMEOUT_SECONDS}s on event #{event}",
          )
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

      # Passes only the kwargs a hook block declares. Lets us extend event
      # payloads (e.g., correlation_id) without breaking hooks written against
      # the old signature.
      def filter_kwargs(callable, kwargs)
        params = callable.parameters
        return kwargs if params.any? { |type, _| type == :keyrest }

        accepted = params.each_with_object([]) do |(type, name), acc|
          acc << name if %i[key keyreq].include?(type)
        end
        kwargs.slice(*accepted)
      end

      def match?(globs, key)
        return true if globs.nil?

        Array(globs).any? { |g| File.fnmatch?(g, key.to_s, File::FNM_PATHNAME) }
      end
    end
  end
end
