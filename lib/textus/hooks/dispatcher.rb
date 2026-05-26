# frozen_string_literal: true

require "timeout"

module Textus
  module Hooks
    class Dispatcher
      HOOK_TIMEOUT_SECONDS = 2

      def initialize
        @subscribers = Hash.new { |h, k| h[k] = [] }
        @error_handlers = []
      end

      # Register an error callback invoked when a user hook raises.
      # Used by Infra::AuditSubscriber to record an "event_error" audit row.
      def on_error(&block)
        @error_handlers << block
      end

      def subscribe(event, name, keys: nil, &block)
        @subscribers[event.to_sym] << { name: name.to_sym, callable: block, keys: keys }
      end

      def publish(event, **kwargs)
        key = kwargs[:key] || "-"
        @subscribers[event.to_sym].each do |sub|
          next unless match?(sub[:keys], key)

          invoke(event, sub, key, kwargs)
        end
      end

      private

      def invoke(event, sub, key, kwargs)
        accepted = filter_kwargs(sub[:callable], kwargs)
        Timeout.timeout(HOOK_TIMEOUT_SECONDS) { sub[:callable].call(**accepted) }
      rescue StandardError => e
        notify_error(event, sub, key, kwargs, e)
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
