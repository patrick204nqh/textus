module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module ValidateKeys
          def self.call(ctx, _deps)
            Textus::Protocol::Manifest::Data.validate_key!(ctx.from_key)
            Textus::Protocol::Manifest::Data.validate_key!(ctx.to_key)
            raise Textus::UsageError.new("old and new keys are identical") if ctx.from_key == ctx.to_key

            ctx
          end
        end

        module ResolvePaths
          def self.call(ctx, deps)
            from_result = deps.manifest.resolver.resolve(ctx.from_key)
            to_result   = deps.manifest.resolver.resolve(ctx.to_key)
            ctx.with(from_path: from_result.path, to_path: to_result.path,
                     from_entry: from_result.entry, to_entry: to_result.entry)
          end
        end

        module AssertSourceExists
          def self.call(ctx, deps)
            return ctx if deps.file_system.exists?(ctx.from_path)

            raise Textus::UnknownKey.new(
              ctx.from_key,
              suggestions: deps.manifest.resolver.suggestions_for(ctx.from_key),
            )
          end
        end

        module AssertTargetNotExists
          def self.call(ctx, deps)
            return ctx unless ctx.to_path && deps.file_system.exists?(ctx.to_path)

            raise Textus::UsageError.new("target '#{ctx.to_key}' already exists")
          end
        end

        module CheckCrossZone
          def self.call(ctx, _deps)
            return ctx if ctx.from_entry.lane == ctx.to_entry.lane

            raise Textus::UsageError.new(
              "cross-zone moves forbidden (#{ctx.from_entry.lane} \u2192 #{ctx.to_entry.lane})",
            )
          end
        end

        module EnsureUid
          def self.call(ctx, deps)
            return ctx if Textus::Infra::Store::Envelope::Meta::NO_META_FORMATS.include?(ctx.from_entry.format)
            return ctx unless ctx.from_path && deps.file_system.exists?(ctx.from_path)

            raw = deps.file_system.read(ctx.from_path)
            parsed = Textus::Protocol::Format.for(ctx.from_entry.format).parse(raw, path: ctx.from_path)
            meta = parsed["_meta"] || {}
            return ctx if meta["uid"].is_a?(String) && !meta["uid"].empty?

            new_meta = Textus::Infra::Store::Envelope::Meta.inject_all(
              meta, parsed["content"], {},
              format: ctx.from_entry.format
            ).first
            bytes, = Textus::Protocol::Format.for(ctx.from_entry.format).serialize_for_put(
              meta: new_meta, body: parsed["body"] || "", content: parsed["content"], path: ctx.from_path,
            )
            deps.file_system.write(ctx.from_path, bytes)
            ctx
          end
        end

        module ReadMoveEtagBefore
          def self.call(ctx, deps)
            etag_before = deps.file_system.etag(ctx.from_path)
            ctx.with(etag_before:)
          end
        end

        module CheckMoveEtag
          def self.call(ctx, _deps)
            return ctx unless ctx.if_etag

            raise Textus::EtagMismatch.new(ctx.from_key, ctx.if_etag, ctx.etag_before) if ctx.etag_before != ctx.if_etag

            ctx
          end
        end

        module MoveFile
          def self.call(ctx, deps)
            deps.file_system.mv(ctx.from_path, ctx.to_path)
            ctx
          end
        end

        module PruneSourceParents
          def self.call(ctx, deps)
            Pipeline.prune_parents(ctx.from_path, deps)
            ctx
          end
        end

        module RewriteBasename
          def self.call(ctx, _deps)
            basename = ctx.to_key.split(".").last
            Textus::Protocol::Format.for(ctx.to_entry.format).rewrite_name(ctx.to_path, basename)
            ctx
          end
        end

        module ReadEtagAfter
          def self.call(ctx, _deps)
            etag_after = Textus::Value::Etag.for_file(ctx.to_path)
            ctx.with(etag_after:)
          end
        end

        module ReadEnvelope
          def self.call(ctx, deps)
            envelope = deps.reader.read(key: ctx.to_key)
            ctx.with(envelope:)
          end
        end

        module AppendMoveAudit
          def self.call(ctx, deps)
            deps.audit_log.append(
              role: deps.call.role, verb: "key_mv", key: ctx.to_key,
              etag_before: ctx.etag_before, etag_after: ctx.etag_after,
              correlation_id: deps.call.correlation_id
            )
            ctx
          end
        end

        module ReindexEntry
          def self.call(ctx, deps)
            deps.entry_index.remove(key: ctx.from_key)
            content = ctx.envelope.content ? ctx.envelope.content.to_json : ctx.envelope.body
            deps.entry_index.record(
              key: ctx.to_key, lane: ctx.to_entry.lane, format: ctx.to_entry.format,
              schema: ctx.to_entry.schema, content: content
            )
            ctx
          end
        end

        module EmitWorkflowEvent
          def self.call(ctx, deps)
            return ctx unless deps.workflow_registry
            return ctx if deps.store.workflow_queue.pending?(event_type: "entry.moved", key: ctx.from_key)
            return ctx if deps.store.workflow_queue.pending?(event_type: "entry.moved", key: ctx.to_key)

            Pipeline.emit_event(ctx, deps,
              event_type: "entry.moved", pending_key: ctx.from_key,
              emit_key: ctx.to_key, emit_lane: ctx.to_entry.lane)
          end
        end

        VALIDATION_STEPS = [
          ValidateKeys,
          ResolvePaths,
          AssertSourceExists,
          AssertTargetNotExists,
          CheckCrossZone,
          EnsureUid,
          ReadMoveEtagBefore,
          CheckMoveEtag,
        ].freeze

        MUTATE_STEPS = [
          MoveFile,
          PruneSourceParents,
          RewriteBasename,
          ReadEtagAfter,
          ReadEnvelope,
          AppendMoveAudit,
          EmitWorkflowEvent,
          ReindexEntry,
        ].freeze

        def self.call(from_key:, to_key:, if_etag: nil, dry_run: false, deps:)
          ctx = Pipeline::MoveContext.new(
            from_key:, to_key:, if_etag:,
            from_path: nil, to_path: nil,
            from_entry: nil, to_entry: nil,
            etag_before: nil, etag_after: nil, envelope: nil, dry_run:
          )
          steps = dry_run ? VALIDATION_STEPS : VALIDATION_STEPS + MUTATE_STEPS
          steps.reduce(ctx) { |c, step| step.call(c, deps) }
        end
      end
    end
  end
end
