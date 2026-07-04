module Textus
  module Protocol
    module WritePipeline
      module Move
        module ResolvePaths
          def self.call(ctx, deps)
            from_path = deps.manifest.resolver.resolve(ctx.from_key).path
            to_path   = deps.manifest.resolver.resolve(ctx.to_key).path
            ctx.with(from_path:, to_path:)
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
            floor = deps.layout.lane_floor(ctx.from_path)
            if floor
              dir = File.dirname(ctx.from_path)
              while dir.start_with?("#{floor}/") && deps.file_system.dir_empty?(dir)
                deps.file_system.rmdir(dir)
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
            Textus::Protocol::Format.for(ctx.new_mentry.format).rewrite_name(ctx.to_path, basename)
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
            envelope = deps.reader.read(ctx.to_key)
            ctx.with(envelope:)
          end
        end

        module AppendMoveAudit
          def self.call(ctx, deps)
            deps.audit_log.append_audit(
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
              key: ctx.to_key, lane: ctx.new_mentry.lane, format: ctx.new_mentry.format,
              schema: ctx.new_mentry.schema, content: content
            )
            ctx
          end
        end

        module EmitWorkflowEvent
          def self.call(ctx, deps)
            return ctx unless deps.workflow_registry
            return ctx if Textus::Protocol::Produce::Engine.converging?(ctx.key) || Textus::Protocol::Produce::Engine.converging?(ctx.to_key)

            emitter = Textus::Protocol::Events::Emitter.new(
              event_store: deps.audit_log,
              workflow_registry: deps.workflow_registry,
            )
            emitter.emit(event_type: "entry.moved", key: ctx.to_key, lane: ctx.new_mentry.lane)
            ctx
          rescue StandardError => e
            warn "textus: emit_workflow_event(entry.moved, #{ctx.key}) failed: #{e.message}"
          end
        end

        STEPS = [
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
          EmitWorkflowEvent,
          ReindexEntry,
        ].freeze

        # rubocop:disable Metrics/ParameterLists
        def self.call(
          from_key:, to_key:, new_mentry:, call:, file_system:, manifest:, store:,
          layout:, reader:, if_etag: nil, workflow_registry: nil
        )
          ctx = MoveContext.new(
            from_key:, to_key:, new_mentry:, if_etag:,
            from_path: nil, to_path: nil,
            etag_before: nil, etag_after: nil, envelope: nil
          )
          deps = WriteDeps.new(file_system:, manifest:, store:, call:, reader:, layout:, workflow_registry:)
          ctx = STEPS.reduce(ctx) { |c, step| step.call(c, deps) }
          ctx.envelope
        end
        # rubocop:enable Metrics/ParameterLists
      end
    end
  end
end
