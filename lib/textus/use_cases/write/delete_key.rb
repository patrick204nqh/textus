module Textus
  module UseCases
    module Write
      module DeleteKey
        HANDLES = Dispatch::Contracts::DeleteKey
        NEEDS = %i[file_system manifest audit_log layout event_store writer reader workflows].freeze

        def self.call(command, call, deps)
          writer = deps.writer
          writer.delete(command.key, if_etag: command.if_etag, call: call)
          registry = Textus::Workflow::Registry.new(deps.workflows)
          emitter = Textus::Produce::EventEmitter.new(db: deps.event_store.db, workflow_registry: registry)
          emitter.emit(event_type: "entry.deleted", key: command.key)
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "key" => command.key, "deleted" => true)
        end
      end
    end
  end
end
