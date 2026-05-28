module Textus
  module Application
    module Write
      class Delete
        def initialize(container:, call:, hook_context:)
          @container    = container
          @call         = call
          @manifest     = container.manifest
          @authorizer   = container.authorizer
          @events       = container.events
          @hook_context = hook_context
        end

        def call(key, if_etag: nil, suppress_events: false)
          Textus::Manifest::Data.validate_key!(key)
          mentry = @manifest.resolver.resolve(key).entry

          @authorizer.authorize_write!(mentry, role: @call.role)

          writer.delete(key, mentry: mentry, if_etag: if_etag)

          unless suppress_events
            @events.publish(:entry_deleted,
                            ctx: @hook_context,
                            key: key)
          end

          { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
        end

        private

        def writer
          @writer ||= Textus::Application::Envelope::Writer.new(
            file_store: @container.file_store,
            manifest: @container.manifest,
            schemas: @container.schemas,
            audit_log: @container.audit_log,
            ctx: @call,
            reader: reader,
          )
        end

        def reader
          @reader ||= Textus::Application::Envelope::Reader.new(
            file_store: @container.file_store,
            manifest: @container.manifest,
          )
        end

        # Back-compat shim: Accept/Reject (still Modules) construct Delete::Impl
        # with the old (ctx:, caps:, writer:, hook_context:) shape. Maps onto the
        # new class. Removed when Accept/Reject are collapsed in Phase 5.
        class Impl
          def initialize(ctx:, caps:, writer:, hook_context:)
            container = Textus::Container.new(
              manifest: caps.manifest, file_store: caps.file_store,
              schemas: caps.schemas, root: caps.root,
              audit_log: caps.audit_log, events: caps.events,
              rpc: nil, authorizer: caps.authorizer
            )
            call_value = Textus::Call.new(
              role: ctx.role, correlation_id: ctx.correlation_id,
              now: ctx.now, dry_run: ctx.dry_run
            )
            @impl = Delete.new(
              container: container, call: call_value, hook_context: hook_context,
            )
            @impl.instance_variable_set(:@writer, writer)
          end

          def call(*, **)
            @impl.call(*, **)
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:delete, Textus::Application::Write::Delete, caps: :write)
