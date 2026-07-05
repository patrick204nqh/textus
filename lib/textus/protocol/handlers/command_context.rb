module Textus
  module Protocol
    module Handlers
      class CommandContext < QueryContext
        # StoreEngine delegation (write side)
        def put(...)    = @store_engine.put(...)
        def delete(...) = @store_engine.delete(...)
        def move(...)   = @store_engine.move(...)

        # Infrastructure (ops, drain, pulse)
        def audit_log         = @container.store.audit_log
        def workflow_queue    = @container.store.workflow_queue
        def file_system       = @container.store.file_system
        def workflows         = @container.workflows
        def workflow_registry = @container.workflow_registry
      end
    end
  end
end
