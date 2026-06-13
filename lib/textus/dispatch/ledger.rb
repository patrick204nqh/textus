# frozen_string_literal: true

module Textus
  module Dispatch
    # Records every event to the audit log before execution.
    # Wraps execution with a block - the record is the intent, not the outcome.
    # Never raises; a failed record logs to stderr and execution continues.
    class Ledger
      def initialize(container)
        @audit_log = container.audit_log
      end

      def record(event)
        return yield if skip_audit?(event)

        begin
          write_row(event)
        rescue StandardError => e
          warn "[Textus::Dispatch::Ledger] audit write failed: #{e.message}"
        end

        yield
      end

      private

      def skip_audit?(event)
        payload = event.payload
        payload.is_a?(Hash) && payload[:__dispatch_audit] == false
      end

      def write_row(event)
        @audit_log.append(
          role: event.actor,
          verb: event.name,
          key: event.target,
          etag_before: nil,
          etag_after: nil,
          extras: { "correlation_id" => event.correlation_id }.compact,
        )
      end
    end
  end
end
