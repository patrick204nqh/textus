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
        def self.from(container:, call:)
          # If the container exposes a writer factory (in tests we set this),
          # use it. Otherwise, construct a fresh Writer.
          return container.writer.call(call) if container.respond_to?(:writer) && container.writer

          new(
            file_store: container.file_store, manifest: container.manifest,
            schemas: container.schemas, audit_log: container.audit_log,
            call: call, reader: Reader.from(container: container),
            layout: container.layout
          )
        end

        def initialize(file_store:, manifest:, schemas:, audit_log:, call:, reader:, layout:)
          @file_store = file_store
          @manifest   = manifest
          @schemas    = schemas
          @audit_log  = audit_log
          @call       = call
          @reader     = reader
          @layout     = layout
        end

        def put(key, mentry:, payload:, if_etag: nil)
          ctx = WriteStep::WriteContext.new(
            key:, mentry:, payload:, if_etag:,
            path: nil, existing_env: nil, meta: nil, content: nil,
            bytes: nil, eff_meta: nil, eff_body: nil, eff_content: nil,
            etag_before: nil, envelope: nil
          )
          deps = WriteStep::WriteDeps.new(
            file_store: @file_store, manifest: @manifest, schemas: @schemas,
            audit_log: @audit_log, call: @call, reader: @reader, layout: @layout
          )
          ctx = WriteStep::DEFAULT_PUT.reduce(ctx) { |c, step| step.call(c, deps) }
          ctx.envelope
        end

        def delete(key, mentry: nil, if_etag: nil) # rubocop:disable Lint/UnusedMethodArgument
          # `mentry:` is accepted for symmetry with `put` / `move` and to
          # leave room for future format-specific delete hooks; no field
          # on it is needed today.
          path = @manifest.resolver.resolve(key).path
          raise UnknownKey.new(key, suggestions: @manifest.resolver.suggestions_for(key)) unless @file_store.exists?(path)

          etag_before = @file_store.etag(path)
          raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && if_etag != etag_before

          @file_store.delete(path)
          prune_empty_parents(path)
          @audit_log.append(
            role: @call.role, verb: "key_delete", key: key,
            etag_before: etag_before, etag_after: nil,
            extras: @call.correlation_id ? { "correlation_id" => @call.correlation_id } : nil
          )
        end

        def move(from_key:, to_key:, new_mentry:, if_etag: nil)
          from_path = @manifest.resolver.resolve(from_key).path
          to_path   = @manifest.resolver.resolve(to_key).path
          raise UnknownKey.new(from_key, suggestions: @manifest.resolver.suggestions_for(from_key)) unless @file_store.exists?(from_path)

          etag_before = @file_store.etag(from_path)
          raise EtagMismatch.new(from_key, if_etag, etag_before) if if_etag && if_etag != etag_before

          @file_store.mv(from_path, to_path)
          prune_empty_parents(from_path)
          basename = to_key.split(".").last
          Format.for(new_mentry.format).rewrite_name(to_path, basename)
          etag_after = Value::Etag.for_file(to_path)

          envelope = @reader.read(to_key)

          extras = {
            "from_key" => from_key, "to_key" => to_key,
            "from_path" => from_path, "to_path" => to_path,
            "uid" => envelope.uid
          }
          extras["correlation_id"] = @call.correlation_id if @call.correlation_id

          @audit_log.append(
            role: @call.role, verb: "key_mv", key: to_key,
            etag_before: etag_before, etag_after: etag_after,
            extras: extras
          )

          envelope
        end

        private

        # After a file leaves a directory (delete or move-source), remove any
        # now-empty parent dirs so bulk move/delete doesn't accrue orphan dirs
        # (F3 of #161). Floored at the entry's *zone directory* — a zone is a
        # declared, first-class container, so its own dir is preserved even when
        # momentarily empty; only the sub-dirs the bulk op carved out are
        # pruned. Stops at the first non-empty ancestor, so a dir holding a
        # `.gitkeep` or sibling entries survives. Best-effort: a lost race or a
        # non-empty dir is silently fine, never fatal to the write.
        def prune_empty_parents(path)
          floor = @layout.lane_floor(path)
          return unless floor

          dir = File.dirname(path)
          while dir.start_with?("#{floor}/") && @file_store.dir_empty?(dir)
            @file_store.rmdir(dir)
            dir = File.dirname(dir)
          end
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
