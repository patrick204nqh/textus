# frozen_string_literal: true

module Textus
  module Dispatch
    module Middleware
      # Shadows successful write operations into the SQLite audit_events table
      # synchronously after dispatch, without the command knowing. Read verbs
      # and failed writes pass through unchanged.
      class AuditIndex < Base
        middleware_name :audit_index

        INDEXED_CONTRACTS = [
          Contracts::PutEntry,
          Contracts::DeleteKey,
          Contracts::MoveKey,
        ].freeze

        def initialize(job_store:, audit_log:)
          super()
          @job_store = job_store
          @audit_log = audit_log
        end

        def call(container:, command:, call:, next_handler:)
          result = next_handler.call(command, call)
          return result unless result.success? && INDEXED_CONTRACTS.include?(command.class)

          key = command.respond_to?(:key) ? command.key : nil
          return result unless key

          emit_entry_written(container, command, call, result, key)

          seq = @audit_log.latest_seq
          verb = command.class.name.split("::").last
                        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                        .downcase

          @job_store.insert_audit_event(
            seq: seq,
            ts: Time.now.utc.iso8601,
            role: call.role,
            verb: verb,
            key: key,
            etag_before: nil,
            etag_after: result.value.is_a?(Hash) ? result.value["etag"] : nil,
          )
          result
        end

        def emit_entry_written(container, command, call, result, key)
          return unless command.instance_of?(Contracts::PutEntry)
          return unless container.respond_to?(:event_bus) && container.event_bus

          etag_after = if result.value.respond_to?(:etag)
                         result.value.etag
                       elsif result.value.is_a?(Hash)
                         result.value["etag"]
                       end

          container.event_bus.emit(Textus::Event::EntryWritten.new(
                                     key: key,
                                     role: call.role,
                                     etag_before: nil,
                                     etag_after: etag_after,
                                     occurred_at: call.now,
                                   ))
        end
      end
    end
  end
end
