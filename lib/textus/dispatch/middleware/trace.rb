module Textus
  module Dispatch
    module Middleware
      class Trace < Base
        middleware_name :trace

        def call(container:, command:, call:, next_handler:)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          error = nil

          next_handler.call(command, call)
        rescue StandardError => e
          error = "#{e.class}: #{e.message}"
          raise
        ensure
          duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
          verb = Textus::VerbRegistry.contract_to_verb(command.class).to_sym
          key = extract_key(command)
          trace = Value::Trace.record(
            verb:, duration_ms: duration,
            correlation_id: call.correlation_id,
            role: call.role, key:, error:
          )
          container.trace_buffer.append(trace) if container.respond_to?(:trace_buffer)
        end

        private

        def extract_key(command)
          if command.respond_to?(:key) then command.key
          elsif command.respond_to?(:old_key) then command.old_key
          elsif command.respond_to?(:pending_key) then command.pending_key
          elsif command.respond_to?(:from) then command.from
          end
        end
      end
    end
  end
end
