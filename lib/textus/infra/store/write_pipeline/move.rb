module Textus
  module Infra
  class Store
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
          ReindexEntry,
        ].freeze

        # rubocop:disable Metrics/ParameterLists
        def self.call(
          from_key:, to_key:, new_mentry:, call:, file_system:, manifest:, audit_log:,
          layout:, reader:, entry_index:, if_etag: nil
        )
          ctx = MoveContext.new(
            from_key:, to_key:, new_mentry:, if_etag:,
            from_path: nil, to_path: nil,
            etag_before: nil, etag_after: nil, envelope: nil
          )
          deps = WriteDeps.new(file_system:, manifest:, audit_log:, call:, reader:, layout:, entry_index:)
          ctx = STEPS.reduce(ctx) { |c, step| step.call(c, deps) }
          ctx.envelope
        end
        # rubocop:enable Metrics/ParameterLists
      end
    end
  end
  end
end
