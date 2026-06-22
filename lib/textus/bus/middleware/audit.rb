module Textus
  module Bus
    module Middleware
      class Audit < Base
        middleware_name :audit

        def call(container:, command:, call:, next_handler:)
          result = next_handler.call(command, call)
          return result unless result.success?

          log(container.audit_log, command, call, result.value)
          result
        end

        private

        def log(audit_log, command, call, envelope)
          audit_log.append(
            role: call.role, verb: Bus.contract_to_verb(command.class),
            key: key_for(command),
            etag_before: nil,
            etag_after: envelope.respond_to?(:etag) ? envelope.etag : nil
          )
        rescue StandardError
          nil
        end

        def key_for(command)
          if command.respond_to?(:key)
            command.key
          else
            command.respond_to?(:old_key) ? command.old_key : nil
          end
        end
      end
    end
  end
end
