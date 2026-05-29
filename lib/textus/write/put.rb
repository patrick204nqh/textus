module Textus
  module Write
    class Put
      def initialize(container:, call:, hook_context:)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @authorizer   = container.authorizer
        @events       = container.events
        @hook_context = hook_context
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
                        ctx: @hook_context,
                        key: key,
                        envelope: envelope)

        envelope
      end

      private

      def writer
        @writer ||= Textus::Envelope::IO::Writer.new(
          file_store: @container.file_store,
          manifest: @container.manifest,
          schemas: @container.schemas,
          audit_log: @container.audit_log,
          ctx: @call,
          reader: reader,
        )
      end

      def reader
        @reader ||= Textus::Envelope::IO::Reader.new(
          file_store: @container.file_store,
          manifest: @container.manifest,
        )
      end
    end
  end
end
