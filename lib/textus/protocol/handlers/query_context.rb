module Textus
  module Protocol
    module Handlers
      class QueryContext
        def initialize(store_engine, container, call)
          @store_engine = store_engine
          @container = container
          @call = call
        end

        attr_reader :call, :store_engine, :container

        # StoreEngine delegation (read side)
        def read(key:)       = @store_engine.read(key:)
        def resolve(key:)    = @store_engine.resolve(key:)
        def list(...)        = @store_engine.list(...)
        def exists?(key:)    = @store_engine.exists?(key:)
        def mentry_for(key:) = @store_engine.mentry_for(key:)

        # Narrow file queries (avoid raw file_system access)
        def file_exists?(key)
          path = @store_engine.resolve(key:).path
          @store_engine.file_system.exists?(path)
        end

        def etag_for(key)
          path = @store_engine.resolve(key:).path
          @store_engine.file_system.etag(path) if @store_engine.file_system.exists?(path)
        end

        # Container metadata (read-only)
        def manifest     = @container.manifest
        def schemas      = @container.schemas
        def layout       = @container.layout
        def link_store   = @container.store.link_store
        def entry_index  = @container.store.entry_index
        def cursor_store = @container.store.cursor_store
      end
    end
  end
end
