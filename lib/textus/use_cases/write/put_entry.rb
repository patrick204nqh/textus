module Textus
  module UseCases
    module Write
      module PutEntry
        HANDLES = Dispatch::Contracts::PutEntry
        NEEDS = %i[file_system manifest audit_log layout event_store writer reader workflows].freeze

        def self.call(command, call, deps)
          writer = deps.writer
          envelope = writer.put(
            command.key,
            mentry: deps.manifest.resolver.resolve(command.key).entry,
            payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content),
            if_etag: command.if_etag, call: call
          )
          registry = Textus::Workflow::Registry.new(deps.workflows)
          emitter = Textus::Produce::EventEmitter.new(db: deps.event_store.db, workflow_registry: registry)
          emitter.emit(event_type: "entry.written", key: command.key)
          Value::Result.success(envelope)
        end
      end
    end
  end
end
