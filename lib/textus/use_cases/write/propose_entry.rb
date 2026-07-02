module Textus
  module UseCases
    module Write
      class ProposeEntry < Base
        handles Dispatch::Contracts::ProposeEntry
        needs :file_system, :manifest, :audit_log, :layout, :writer, :reader

        def call
          zone = manifest.policy.propose_lane_for(call.role)
          unless zone
            return failure(:propose_forbidden,
                           "role '#{call.role}' has no writable propose_lane",
                           details: { "role" => call.role })
          end

          key = "#{zone}.#{command.key}"
          mentry = manifest.resolver.resolve(key).entry
          writer.put(
            key, mentry: mentry, call: call,
                 payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content)
          ).then { |envelope| success(envelope) }
        end
      end
    end
  end
end
