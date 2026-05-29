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
      end
    end
  end
end
