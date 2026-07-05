module Textus
  module Protocol
    class StoreEngine
      module Pipeline
        WriteContext = Data.define(
          :key, :mentry, :payload, :if_etag,
          :path, :existing_env, :meta, :content,
          :bytes, :eff_meta, :eff_body, :eff_content,
          :etag_before, :envelope
        ) do
          def with(**attrs) = self.class.new(**to_h, **attrs)
        end

        WriteDeps = Data.define(:file_system, :manifest, :store, :call, :reader, :layout, :workflow_registry) do
          def audit_log    = store.audit_log
          def entry_index  = store.entry_index
          def file_store   = store.file_store
        end

        DeleteContext = Data.define(:key, :if_etag, :path, :etag_before) do
          def with(**attrs) = self.class.new(**to_h, **attrs)
        end

        MoveContext = Data.define(:from_key, :to_key, :if_etag,
                                  :from_path, :to_path, :from_entry, :to_entry,
                                  :etag_before, :etag_after, :envelope, :dry_run) do
          def with(**attrs) = self.class.new(**to_h, **attrs)
        end
      end
    end
  end
end
