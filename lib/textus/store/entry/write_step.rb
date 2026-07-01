module Textus
  class Store
    module Entry
      module WriteStep
        WriteContext = Data.define(
          :key, :mentry, :payload, :if_etag,
          :path, :existing_env,
          :meta, :content,
          :bytes, :eff_meta, :eff_body, :eff_content,
          :etag_before, :envelope
        ) do
          def with(**attrs) = self.class.new(**to_h, **attrs)
        end

        WriteDeps = Data.define(
          :file_store, :manifest, :schemas, :audit_log, :call, :reader, :layout
        )

        module ResolvePath
          def self.call(ctx, deps)
            path = deps.manifest.resolver.resolve(ctx.key).path
            ctx.with(path:)
          end
        end

        module ReadExisting
          def self.call(ctx, deps)
            existing_env = deps.reader.read(ctx.key)
            ctx.with(existing_env:)
          end
        end

        module InjectMeta
          def self.call(ctx, deps)
            existing_meta = ctx.existing_env ? ctx.existing_env.meta : {}
            raw_meta = ctx.payload.meta || {}
            meta, content = Envelope::Meta.inject_all(
              raw_meta, ctx.payload.content, existing_meta,
              format: ctx.mentry.format,
              etag_for: method(:resolve_source_etag).curry.call(deps)
            )
            ctx.with(meta:, content:)
          end

          def self.resolve_source_etag(deps, key)
            path = deps.manifest.resolver.resolve(key).path
            return nil unless deps.file_store.exists?(path)

            Value::Etag.for_file(path)
          rescue Textus::Error
            nil
          end
        end

        module Serialize
          def self.call(ctx, _deps)
            bytes, eff_meta, eff_body, eff_content =
              Textus::Format.for(ctx.mentry.format).serialize_for_put(
                meta: ctx.meta, body: ctx.payload.body,
                content: ctx.content, path: ctx.path
              )
            ctx.with(bytes:, eff_meta:, eff_body:, eff_content:)
          end
        end

        module EnforceNameMatch
          def self.call(ctx, _deps)
            Textus::Format.for(ctx.mentry.format).enforce_name_match!(ctx.path, ctx.eff_meta)
            ctx
          end
        end

        module ValidateSchema
          def self.call(ctx, deps)
            schema = deps.schemas.fetch_or_nil(ctx.mentry.schema)
            if schema
              Format.for(ctx.mentry.format).validate_against(
                schema,
                { "_meta" => ctx.eff_meta, "content" => ctx.eff_content },
              )
            end
            ctx
          end
        end

        module ValidateRaw
          def self.call(ctx, _deps)
            Textus::Format.for(ctx.mentry.format).validate_raw_entry!(
              { "_meta" => ctx.eff_meta, "content" => ctx.eff_content },
              ctx.mentry.lane,
            )
            ctx
          end
        end

        module CheckEtag
          def self.call(ctx, deps)
            etag_before = deps.file_store.exists?(ctx.path) ? deps.file_store.etag(ctx.path) : nil
            raise EtagMismatch.new(ctx.key, ctx.if_etag, etag_before) if ctx.if_etag && (etag_before != ctx.if_etag)

            ctx.with(etag_before:)
          end
        end

        module WriteBytes
          def self.call(ctx, deps)
            deps.file_store.write(ctx.path, ctx.bytes)
            ctx
          end
        end

        module BuildEnvelope
          def self.call(ctx, _deps)
            envelope = Textus::Value::Envelope.build(
              key: ctx.key, mentry: ctx.mentry, path: ctx.path,
              meta: ctx.eff_meta, body: ctx.eff_body,
              etag: Value::Etag.for_bytes(ctx.bytes),
              content: ctx.eff_content
            )
            ctx.with(envelope:)
          end
        end

        module AppendAudit
          def self.call(ctx, deps)
            extras = deps.call.correlation_id ? { "correlation_id" => deps.call.correlation_id } : nil
            deps.audit_log.append(
              role: deps.call.role, verb: "put", key: ctx.key,
              etag_before: ctx.etag_before, etag_after: ctx.envelope.etag,
              extras:
            )
            ctx
          end
        end

        DEFAULT_PUT = [
          ResolvePath, ReadExisting, InjectMeta, Serialize,
          EnforceNameMatch, ValidateSchema, ValidateRaw,
          CheckEtag, WriteBytes, BuildEnvelope, AppendAudit
        ].freeze

        DeleteContext = Data.define(
          :key, :mentry, :if_etag,
          :path,
          :etag_before
        ) do
          def with(**attrs) = self.class.new(**to_h, **attrs)
        end

        module AssertExists
          def self.call(ctx, deps)
            return ctx if deps.file_store.exists?(ctx.path)

            raise UnknownKey.new(ctx.key, suggestions: deps.manifest.resolver.suggestions_for(ctx.key))
          end
        end

        module DeleteFile
          def self.call(ctx, deps)
            deps.file_store.delete(ctx.path)
            ctx
          end
        end

        module PruneParents
          def self.call(ctx, deps)
            floor = deps.layout.lane_floor(ctx.path)
            if floor
              dir = File.dirname(ctx.path)
              while dir.start_with?("#{floor}/") && deps.file_store.dir_empty?(dir)
                deps.file_store.rmdir(dir)
                dir = File.dirname(dir)
              end
            end
            ctx
          rescue SystemCallError
            ctx
          end
        end

        module AppendDeleteAudit
          def self.call(ctx, deps)
            extras = deps.call.correlation_id ? { "correlation_id" => deps.call.correlation_id } : nil
            deps.audit_log.append(
              role: deps.call.role, verb: "key_delete", key: ctx.key,
              etag_before: ctx.etag_before, etag_after: nil,
              extras:
            )
            ctx
          end
        end

        DEFAULT_DELETE = [
          ResolvePath,
          AssertExists,
          CheckEtag,
          DeleteFile,
          PruneParents,
          AppendDeleteAudit,
        ].freeze

        MoveContext = Data.define(
          :from_key, :to_key, :new_mentry, :if_etag,
          :from_path, :to_path,
          :etag_before,
          :etag_after,
          :envelope
        ) do
          def with(**attrs) = self.class.new(**to_h, **attrs)
        end

        module ResolvePaths
          def self.call(ctx, deps)
            from_path = deps.manifest.resolver.resolve(ctx.from_key).path
            to_path   = deps.manifest.resolver.resolve(ctx.to_key).path
            ctx.with(from_path:, to_path:)
          end
        end

        module AssertSourceExists
          def self.call(ctx, deps)
            return ctx if deps.file_store.exists?(ctx.from_path)

            raise UnknownKey.new(
              ctx.from_key,
              suggestions: deps.manifest.resolver.suggestions_for(ctx.from_key),
            )
          end
        end

        module ReadMoveEtagBefore
          def self.call(ctx, deps)
            etag_before = deps.file_store.etag(ctx.from_path)
            ctx.with(etag_before:)
          end
        end

        module CheckMoveEtag
          def self.call(ctx, _deps)
            return ctx unless ctx.if_etag

            raise EtagMismatch.new(ctx.from_key, ctx.if_etag, ctx.etag_before) if ctx.etag_before != ctx.if_etag

            ctx
          end
        end

        module MoveFile
          def self.call(ctx, deps)
            deps.file_store.mv(ctx.from_path, ctx.to_path)
            ctx
          end
        end

        module PruneSourceParents
          def self.call(ctx, deps)
            floor = deps.layout.lane_floor(ctx.from_path)
            if floor
              dir = File.dirname(ctx.from_path)
              while dir.start_with?("#{floor}/") && deps.file_store.dir_empty?(dir)
                deps.file_store.rmdir(dir)
                dir = File.dirname(dir)
              end
            end
            ctx
          rescue SystemCallError
            ctx
          end
        end

        module RewriteBasename
          def self.call(ctx, _deps)
            basename = ctx.to_key.split(".").last
            Format.for(ctx.new_mentry.format).rewrite_name(ctx.to_path, basename)
            ctx
          end
        end

        module ReadEtagAfter
          def self.call(ctx, _deps)
            etag_after = Value::Etag.for_file(ctx.to_path)
            ctx.with(etag_after:)
          end
        end

        module ReadEnvelope
          def self.call(ctx, deps)
            envelope = deps.reader.read(ctx.to_key)
            ctx.with(envelope:)
          end
        end

        module AppendMoveAudit
          def self.call(ctx, deps)
            extras = {
              "from_key" => ctx.from_key, "to_key" => ctx.to_key,
              "from_path" => ctx.from_path, "to_path" => ctx.to_path,
              "uid" => ctx.envelope.uid
            }
            extras["correlation_id"] = deps.call.correlation_id if deps.call.correlation_id
            deps.audit_log.append(
              role: deps.call.role, verb: "key_mv", key: ctx.to_key,
              etag_before: ctx.etag_before, etag_after: ctx.etag_after,
              extras:
            )
            ctx
          end
        end

        DEFAULT_MOVE = [
          ResolvePaths,
          AssertSourceExists,
          ReadMoveEtagBefore,
          CheckMoveEtag,
          MoveFile,
          PruneSourceParents,
          RewriteBasename,
          ReadEtagAfter,
          ReadEnvelope,
          AppendMoveAudit,
        ].freeze
      end
    end
  end
end
