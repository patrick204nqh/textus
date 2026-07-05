module Textus
  module Protocol
    class StoreEngine
      module Pipeline
        module ContextWith
          def with(**attrs) = self.class.new(**to_h, **attrs)
        end

        WriteContext = Data.define(
          :key, :mentry, :payload, :if_etag,
          :path, :existing_env, :meta, :content,
          :bytes, :eff_meta, :eff_body, :eff_content,
          :etag_before, :envelope
        ) do
          include ContextWith
        end

        WriteDeps = Data.define(:file_system, :manifest, :store, :call, :reader, :layout, :workflow_registry) do
          def audit_log    = store.audit_log
          def entry_index  = store.entry_index
          def file_store   = store.file_store
        end

        DeleteContext = Data.define(:key, :if_etag, :path, :etag_before) do
          include ContextWith
        end

        MoveContext = Data.define(:from_key, :to_key, :if_etag,
                                  :from_path, :to_path, :from_entry, :to_entry,
                                  :etag_before, :etag_after, :envelope, :dry_run) do
          include ContextWith
        end

        module_function

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

        def emit_event(ctx, deps, event_type:, pending_key:, emit_key:, emit_lane: nil)
          return ctx unless deps.workflow_registry
          return ctx if deps.store.workflow_queue.pending?(event_type:, key: pending_key)

          Textus::Workflow::Queue.new(
            deps.store.workflow_queue,
            registry: deps.workflow_registry,
            container: deps,
            call: deps.call,
          ).enqueue(event_type:, key: emit_key, lane: emit_lane || "artifacts")
          ctx
        rescue StandardError => e
          warn "textus: emit_workflow_event(#{event_type}, #{emit_key}) failed: #{e.message}"
          ctx
        end
      end
    end
  end
end
