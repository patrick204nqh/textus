module Textus
  module Protocol
    module WritePipeline
      module Delete
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
            floor = deps.layout.lane_floor(ctx.path)
            if floor
              dir = File.dirname(ctx.path)
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

        module AppendDeleteAudit
          def self.call(ctx, deps)
            deps.audit_log.append_audit(
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

        STEPS = [
          ResolvePath,
          AssertExists,
          CheckEtag,
          DeleteFile,
          PruneParents,
          AppendDeleteAudit,
          DeindexEntry,
        ].freeze

        # rubocop:disable Metrics/ParameterLists
        def self.call(key, call:, file_system:, manifest:, store:, layout:, mentry: nil, if_etag: nil, reader: nil)
          ctx = DeleteContext.new(
            key:, mentry:, if_etag:,
            path: nil, etag_before: nil
          )
          deps = WriteDeps.new(file_system:, manifest:, store:, call:, reader:, layout:)
          STEPS.reduce(ctx) { |c, step| step.call(c, deps) }
          nil
        end
        # rubocop:enable Metrics/ParameterLists
      end
    end
  end
end
