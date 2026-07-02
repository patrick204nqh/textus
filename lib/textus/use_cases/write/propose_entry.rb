module Textus
  module UseCases
    module Write
      module ProposeEntry
        HANDLES = Dispatch::Contracts::ProposeEntry
        NEEDS = %i[file_system manifest audit_log layout event_store writer reader workflows].freeze

        def self.call(command, call, deps)
          zone = deps.manifest.policy.propose_lane_for(call.role)
          unless zone
            return Value::Result.failure(:propose_forbidden,
                                         "role '#{call.role}' has no writable propose_lane",
                                         details: { "role" => call.role })
          end

          key = "#{zone}.#{command.key}"
          mentry = deps.manifest.resolver.resolve(key).entry
          writer = deps.writer
          envelope = writer.put(
            key, mentry: mentry, call: call,
                 payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content)
          )
          registry = Textus::Workflow::Registry.new(deps.workflows)
          emitter = Textus::Produce::EventEmitter.new(db: deps.event_store.db, workflow_registry: registry)
          emitter.emit(event_type: "entry.written", key: key)
          Value::Result.success(envelope)
        end
      end
    end
  end
end
