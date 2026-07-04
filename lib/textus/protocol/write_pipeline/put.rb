module Textus
  module Protocol
    module WritePipeline
      module Put
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
            meta, content = Textus::Infra::Store::Envelope::Meta.inject_all(
              raw_meta, ctx.payload.content, existing_meta,
              format: ctx.mentry.format,
              etag_for: method(:resolve_source_etag).curry.call(deps)
            )
            ctx.with(meta:, content:)
          end

          def self.resolve_source_etag(deps, key)
            path = deps.manifest.resolver.resolve(key).path
            return nil unless deps.file_system.exists?(path)

            Textus::Value::Etag.for_file(path)
          rescue Textus::Error
            nil
          end
        end

        module Serialize
          def self.call(ctx, _deps)
            bytes, eff_meta, eff_body, eff_content =
              Textus::Protocol::Format.for(ctx.mentry.format).serialize_for_put(
                meta: ctx.meta, body: ctx.payload.body,
                content: ctx.content, path: ctx.path
              )
            ctx.with(bytes:, eff_meta:, eff_body:, eff_content:)
          end
        end

        module EnforceNameMatch
          def self.call(ctx, _deps)
            Textus::Protocol::Format.for(ctx.mentry.format).enforce_name_match!(ctx.path, ctx.eff_meta)
            ctx
          end
        end

        module ValidateRaw
          def self.call(ctx, _deps)
            Textus::Protocol::Format.for(ctx.mentry.format).validate_raw_entry!(
              { "_meta" => ctx.eff_meta, "content" => ctx.eff_content },
              ctx.mentry.lane,
            )
            ctx
          end
        end

        module CheckEtag
          def self.call(ctx, deps)
            etag_before = deps.file_system.exists?(ctx.path) ? deps.file_system.etag(ctx.path) : nil
            raise Textus::EtagMismatch.new(ctx.key, ctx.if_etag, etag_before) if ctx.if_etag && (etag_before != ctx.if_etag)

            ctx.with(etag_before:)
          end
        end

        module WriteBytes
          def self.call(ctx, deps)
            deps.file_system.write(ctx.path, ctx.bytes)
            ctx
          end
        end

        module BuildEnvelope
          def self.call(ctx, _deps)
            envelope = Textus::Protocol::Envelope.build(
              key: ctx.key, mentry: ctx.mentry, path: ctx.path,
              meta: ctx.eff_meta, body: ctx.eff_body,
              etag: Textus::Value::Etag.for_bytes(ctx.bytes),
              content: ctx.eff_content
            )
            ctx.with(envelope:)
          end
        end

        module AppendAudit
          def self.call(ctx, deps)
            deps.call.correlation_id ? { "correlation_id" => deps.call.correlation_id } : nil
            deps.audit_log.append(
              role: deps.call.role, verb: "put", key: ctx.key,
              etag_before: ctx.etag_before, etag_after: ctx.envelope.etag,
              correlation_id: deps.call.correlation_id
            )
            ctx
          end
        end

        module IndexEntry
          def self.call(ctx, deps)
            content = ctx.eff_content ? ctx.eff_content.to_json : ctx.eff_body
            deps.entry_index.record(
              key: ctx.key, lane: ctx.mentry.lane, format: ctx.mentry.format,
              schema: ctx.mentry.schema, content: content
            )
            ctx
          end
        end

        module EmitWorkflowEvent
          def self.call(ctx, deps)
            return ctx unless deps.workflow_registry
            return ctx if Textus::Protocol::Produce::Engine.converging?(ctx.key)

            emitter = Textus::Protocol::Events::Emitter.new(
              workflow_queue: deps.store.workflow_queue,
              workflow_registry: deps.workflow_registry,
            )
            emitter.emit(event_type: "entry.written", key: ctx.key, lane: ctx.mentry.lane)
            ctx
          rescue StandardError => e
            warn "textus: emit_workflow_event(entry.written, #{ctx.key}) failed: #{e.message}"
            ctx
          end
        end

        STEPS = [
          ResolvePath, ReadExisting, InjectMeta, Serialize,
          EnforceNameMatch, ValidateRaw,
          CheckEtag, WriteBytes, BuildEnvelope, AppendAudit, EmitWorkflowEvent, IndexEntry
        ].freeze

        # rubocop:disable Metrics/ParameterLists
        def self.call(key, mentry:, payload:, call:, file_system:, manifest:, store:, layout:, reader:, if_etag: nil, workflow_registry: nil)
          ctx = WriteContext.new(
            key:, mentry:, payload:, if_etag:,
            path: nil, existing_env: nil, meta: nil, content: nil,
            bytes: nil, eff_meta: nil, eff_body: nil, eff_content: nil,
            etag_before: nil, envelope: nil
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
