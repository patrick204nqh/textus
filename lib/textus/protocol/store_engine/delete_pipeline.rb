module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        module ResolvePath
          def self.call(ctx, deps)
            path = deps.manifest.resolver.resolve(ctx.key).path
            ctx.with(path:)
          end
        end

        module CheckEtag
          def self.call(ctx, deps)
            etag_before = deps.file_system.exists?(ctx.path) ? deps.file_system.etag(ctx.path) : nil
            raise Textus::EtagMismatch.new(ctx.key, ctx.if_etag, etag_before) if ctx.if_etag && (etag_before != ctx.if_etag)

            ctx.with(etag_before:)
          end
        end

        module AssertExists
          def self.call(ctx, deps)
            return ctx if deps.file_system.exists?(ctx.path)

            raise Textus::UnknownKey.new(ctx.key, suggestions: deps.manifest.resolver.suggestions_for(ctx.key))
          end
        end

        module DeleteFile
          def self.call(ctx, deps)
            deps.file_system.delete(ctx.path)
            ctx
          end
        end

        module PruneParents
          def self.call(ctx, deps)
            Pipeline.prune_parents(ctx.path, deps)
            ctx
          end
        end

        module AppendDeleteAudit
          def self.call(ctx, deps)
            deps.audit_log.append(
              role: deps.call.role, verb: "key_delete", key: ctx.key,
              etag_before: ctx.etag_before, etag_after: nil,
              correlation_id: deps.call.correlation_id
            )
            ctx
          end
        end

        module DeindexEntry
          def self.call(ctx, deps)
            deps.entry_index.remove(key: ctx.key)
            ctx
          end
        end

        module EmitWorkflowEvent
          def self.call(ctx, deps)
            Pipeline.emit_event(ctx, deps,
                                event_type: "entry.deleted", pending_key: ctx.key,
                                emit_key: ctx.key)
          end
        end

        STEPS = [
          ResolvePath,
          AssertExists,
          CheckEtag,
          DeleteFile,
          PruneParents,
          AppendDeleteAudit,
          EmitWorkflowEvent,
          DeindexEntry,
        ].freeze

        def self.call(key, deps:, if_etag: nil)
          ctx = Pipeline::DeleteContext.new(key:, if_etag:, path: nil, etag_before: nil)
          STEPS.reduce(ctx) { |c, step| step.call(c, deps) }
          nil
        end
      end
    end
  end
end
