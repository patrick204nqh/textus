# frozen_string_literal: true

module Textus
  module Infra
    # Writes an "event_error" audit row when a user hook raises during
    # Hooks::EventBus publish. Attached at Store boot.
    #
    # Integration: uses Hooks::EventBus#on_error callback (chosen over a
    # synthetic :hook_error event because the bus already owns the
    # rescue and the failure is a bus-internal concern, not a domain
    # event subscribers should be able to filter by key glob).
    #
    # Lifecycle audit rows for verb: "put" / "delete" / "rename" are written
    # by Application::Envelope::Writer directly (it owns the
    # audit-append-as-final-step invariant); this subscriber covers the
    # hook-failure case the writer never sees.
    class AuditSubscriber
      def initialize(audit_log)
        @audit_log = audit_log
      end

      def attach(bus)
        bus.on_error do |event:, hook:, key:, kwargs:, error:|
          record_error(event: event, hook: hook, key: key, kwargs: kwargs, error: error)
        end
        self
      end

      private

      def record_error(event:, hook:, key:, kwargs:, error:)
        extras = { "event" => event.to_s, "hook" => hook.to_s, "error" => "#{error.class}: #{error.message}" }
        extras["target_key"]  = kwargs[:target_key]  if kwargs.key?(:target_key)
        extras["pending_key"] = kwargs[:pending_key] if kwargs.key?(:pending_key)
        @audit_log.append(
          role: "runner", verb: "event_error", key: key,
          etag_before: nil, etag_after: nil, extras: extras
        )
      end
    end
  end
end
