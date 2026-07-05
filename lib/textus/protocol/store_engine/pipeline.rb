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
          :etag_before, :envelope, :fmt
        ) do
          include ContextWith

          def format = fmt || mentry.format
        end

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

        DeleteContext = Data.define(:key, :if_etag, :path, :etag_before) do
          include ContextWith
        end

        MoveDeps = Data.define(:file_system, :manifest, :store, :call, :reader, :layout, :event_emitter) do
          def audit_log    = store.audit_log
          def entry_index  = store.entry_index
          def workflow_queue = store.workflow_queue
        end

        MoveContext = Data.define(:from_key, :to_key, :if_etag,
                                  :from_path, :to_path, :from_entry, :to_entry,
                                  :etag_before, :etag_after, :envelope, :dry_run) do
          include ContextWith
        end

        module_function

        def resolve_path(key, deps)
          deps.manifest.resolver.resolve(key).path
        end

        def check_etag(ctx, deps)
          etag_before = deps.file_system.exists?(ctx.path) ? deps.file_system.etag(ctx.path) : nil
          raise Textus::EtagMismatch.new(ctx.key, ctx.if_etag, etag_before) if ctx.if_etag && (etag_before != ctx.if_etag)

          ctx.with(etag_before:)
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

        def emit_event(ctx, deps, event_type:, pending_key:, emit_key:, emit_lane: nil, pending_keys: [])
          return ctx unless deps.event_emitter
          return ctx if deps.store.workflow_queue.pending?(event_type:, key: pending_key)
          return ctx if pending_keys.any? { |k| deps.store.workflow_queue.pending?(event_type:, key: k) }

          deps.event_emitter.emit(event_type:, key: emit_key, lane: emit_lane || "artifacts")
          ctx
        rescue StandardError => e
          warn "textus: emit_workflow_event(#{event_type}, #{emit_key}) failed: #{e.message}"
          ctx
        end
      end
    end
  end
end
