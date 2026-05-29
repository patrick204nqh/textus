module Textus
  module Write
    class Put
      def initialize(container:, call:)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @authorizer   = container.authorizer
        @events       = container.events
      end

      def call(key, meta: nil, body: nil, content: nil, if_etag: nil)
        Textus::Manifest::Data.validate_key!(key)
        mentry = @manifest.resolver.resolve(key).entry
        @authorizer.authorize_write!(mentry, role: @call.role)

        envelope = writer.put(
          key,
          mentry: mentry,
          payload: Textus::Envelope::IO::Writer::Payload.new(
            meta: meta, body: body, content: content,
          ),
          if_etag: if_etag,
        )

        @events.publish(:entry_put,
                        ctx: hook_context,
                        key: key,
                        envelope: envelope)

        envelope
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
