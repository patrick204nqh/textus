module Textus
  module Protocol
    module Handlers
      class Context
        def initialize(container, store_engine:, call:)
          @container = container
          @store_engine = store_engine
          @call = call
        end

        attr_reader :call, :container, :store_engine

        def manifest  = @container.manifest
        def layout    = @container.layout
        def schemas   = @container.schemas
        def workflows = @container.workflows
        def workflow_registry = @container.workflow_registry

        def audit_log      = @container.store.audit_log
        def cursor_store   = @container.store.cursor_store
        def link_store     = @container.store.link_store
        def workflow_queue = @container.store.workflow_queue
        def entry_index    = @container.store.entry_index
        def file_system    = @container.store.file_system

        def read(key:)       = @store_engine.read(key:)
        def resolve(key:)    = @store_engine.resolve(key:)
        def list(...)        = @store_engine.list(...)
        def exists?(key:)    = @store_engine.exists?(key:)
        def mentry_for(key:) = @store_engine.mentry_for(key:)
        def put(...)         = @store_engine.put(...)
        def delete(...)      = @store_engine.delete(...)
        def move(...)        = @store_engine.move(...)
      end
    end
  end
end
