module Textus
  module Application
    module Write
      module Delete
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(
            ctx: ctx, caps: caps,
            writer: session.envelope_writer,
            hook_context: session.hook_context
          ).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, writer:, hook_context:)
            @ctx          = ctx
            @manifest     = caps.manifest
            @events       = caps.events
            @authorizer   = caps.authorizer
            @writer       = writer
            @hook_context = hook_context
          end

          def call(key, if_etag: nil, suppress_events: false)
            Textus::Manifest::Data.validate_key!(key)
            mentry = @manifest.resolver.resolve(key).entry

            @authorizer.authorize_write!(mentry, role: @ctx.role)

            @writer.delete(key, mentry: mentry, if_etag: if_etag)

            unless suppress_events
              @events.publish(:entry_deleted,
                              ctx: @hook_context,
                              key: key)
            end

            { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:delete, Textus::Application::Write::Delete, caps: :write)
