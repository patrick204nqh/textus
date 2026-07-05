module Textus
  module Protocol
    class StoreEngine
      module Pipeline
        WriteDeps = Data.define(:file_system, :manifest, :store, :call, :reader, :layout, :event_emitter, :schemas) do
          def audit_log    = store.audit_log
          def entry_index  = store.entry_index
          def file_store   = store.file_store
        end

        DeleteDeps = Data.define(:file_system, :manifest, :store, :call, :layout, :event_emitter) do
          def audit_log    = store.audit_log
          def entry_index  = store.entry_index
          def workflow_queue = store.workflow_queue
        end

        MoveDeps = Data.define(:file_system, :manifest, :store, :call, :reader, :layout, :event_emitter) do
          def audit_log    = store.audit_log
          def entry_index  = store.entry_index
          def workflow_queue = store.workflow_queue
        end

        module_function

        def resolve_path(key, deps)
          deps.manifest.resolver.resolve(key).path
        end

        def check_etag(key, path, if_etag, file_system)
          etag_before = file_system.exists?(path) ? file_system.etag(path) : nil
          raise Textus::EtagMismatch.new(key, if_etag, etag_before) if if_etag && (etag_before != if_etag)

          etag_before
        end

        def prune_parents(path, deps)
          floor = deps.layout.lane_floor(path)
          return unless floor

          dir = File.dirname(path)
          while dir.start_with?("#{floor}/") && deps.file_system.dir_empty?(dir)
            deps.file_system.rmdir(dir)
            dir = File.dirname(dir)
          end
        rescue SystemCallError
          # race: dir may have been emptied by another writer
        end

        def emit_event(deps, event_type:, pending_key:, emit_key:, emit_lane: nil, pending_keys: [])
          return unless deps.event_emitter
          return if deps.store.workflow_queue.pending?(event_type:, key: pending_key)
          return if pending_keys.any? { |k| deps.store.workflow_queue.pending?(event_type:, key: k) }

          deps.event_emitter.emit(event_type:, key: emit_key, lane: emit_lane || "artifacts")
        rescue StandardError => e
          warn "textus: emit_workflow_event(#{event_type}, #{emit_key}) failed: #{e.message}"
        end
      end
    end
  end
end
