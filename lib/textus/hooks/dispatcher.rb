# frozen_string_literal: true

require "timeout"

module Textus
  module Hooks
    class Dispatcher
      HOOK_TIMEOUT_SECONDS = 2

      def initialize(audit_log:)
        @audit_log = audit_log
        @subscribers = Hash.new { |h, k| h[k] = [] }
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
        extras = { "event" => event.to_s, "hook" => sub[:name].to_s, "error" => "#{e.class}: #{e.message}" }
        extras["target_key"]  = kwargs[:target_key]  if kwargs.key?(:target_key)
        extras["pending_key"] = kwargs[:pending_key] if kwargs.key?(:pending_key)
        @audit_log.append(
          role: "runner", verb: "event_error", key: key,
          etag_before: nil, etag_after: nil, extras: extras
        )
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
