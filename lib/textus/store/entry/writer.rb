require "fileutils"
require_relative "write_step"

module Textus
  class Store
    module Entry
      # Owns the write pipeline (validate, serialize, etag-check, write, audit).
      # Talks to ports (FileStore, Schemas, AuditLog, Manifest) and an
      # Reader for the existing-uid lookup.
      #
      # Invariant: every public method's final action is @audit_log.append(...).
      #
      # No permission check, no event firing — those belong to the caller
      # (Write::Put / ::Delete / ::Mv).
      class Writer
        def initialize(file_store:, manifest:, audit_log:, reader:, layout:)
          @file_store = file_store
          @manifest   = manifest
          @audit_log  = audit_log
          @reader     = reader
          @layout     = layout
        end

        def put(key, mentry:, payload:, call:, if_etag: nil)
          ctx = WriteStep::WriteContext.new(
            key:, mentry:, payload:, if_etag:,
            path: nil, existing_env: nil, meta: nil, content: nil,
            bytes: nil, eff_meta: nil, eff_body: nil, eff_content: nil,
            etag_before: nil, envelope: nil
          )
          deps = WriteStep::WriteDeps.new(
            file_store: @file_store, manifest: @manifest,
            audit_log: @audit_log, call:, reader: @reader, layout: @layout
          )
          ctx = WriteStep::DEFAULT_PUT.reduce(ctx) { |c, step| step.call(c, deps) }
          ctx.envelope
        end

        def delete(key, call:, mentry: nil, if_etag: nil)
          ctx = WriteStep::DeleteContext.new(
            key:, mentry:, if_etag:,
            path: nil, etag_before: nil
          )
          deps = WriteStep::WriteDeps.new(
            file_store: @file_store, manifest: @manifest,
            audit_log: @audit_log, call:, reader: @reader, layout: @layout
          )
          WriteStep::DEFAULT_DELETE.reduce(ctx) { |c, step| step.call(c, deps) }
          nil
        end

        def move(from_key:, to_key:, new_mentry:, call:, if_etag: nil)
          ctx = WriteStep::MoveContext.new(
            from_key:, to_key:, new_mentry:, if_etag:,
            from_path: nil, to_path: nil,
            etag_before: nil, etag_after: nil, envelope: nil
          )
          deps = WriteStep::WriteDeps.new(
            file_store: @file_store, manifest: @manifest,
            audit_log: @audit_log, call:, reader: @reader, layout: @layout
          )
          ctx = WriteStep::DEFAULT_MOVE.reduce(ctx) { |c, step| step.call(c, deps) }
          ctx.envelope
        end
      end
    end
  end
end
