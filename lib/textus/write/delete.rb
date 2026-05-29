module Textus
  module Write
    class Delete
      def initialize(container:, call:)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @authorizer   = container.authorizer
        @events       = container.events
      end

      def call(key, if_etag: nil, suppress_events: false)
        Textus::Manifest::Data.validate_key!(key)
        mentry = @manifest.resolver.resolve(key).entry

        @authorizer.authorize_write!(mentry, role: @call.role)

        writer.delete(key, mentry: mentry, if_etag: if_etag)

        unless suppress_events
          @events.publish(:entry_deleted,
                          ctx: hook_context,
                          key: key)
        end

        { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
      end

      private

      def hook_context
        @hook_context ||= Textus::Hooks::Context.for(container: @container, call: @call)
      end

      def writer
        @writer ||= Textus::Envelope::IO::Writer.from(container: @container, call: @call)
      end
    end
  end
end
