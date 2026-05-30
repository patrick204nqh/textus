module Textus
  module Write
    class Delete
      def initialize(container:, call:)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @events       = container.events
      end

      def call(key, if_etag: nil, suppress_events: false)
        Textus::Manifest::Data.validate_key!(key)
        mentry = @manifest.resolver.resolve(key).entry

        guard_for(:delete, key, if_etag: if_etag).check!(eval_for(:delete, target_key: key))

        writer.delete(key, mentry: mentry, if_etag: if_etag)

        unless suppress_events
          @events.publish(:entry_deleted,
                          ctx: hook_context,
                          key: key)
        end

        { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
      end

      private

      def guard_for(transition, key, if_etag: nil)
        Textus::Domain::Policy::GuardFactory.new(
          manifest: @manifest, schemas: @container.schemas, extra: { if_etag: if_etag },
        ).for(transition, key)
      end

      def eval_for(transition, target_key:, envelope: nil)
        Textus::Domain::Policy::Evaluation.new(
          actor: @call.role, transition: transition, origin: nil,
          target: target_key, envelope: envelope, snapshot: @manifest
        )
      end

      def hook_context
        @hook_context ||= Textus::Hooks::Context.for(container: @container, call: @call)
      end

      def writer
        @writer ||= Textus::Envelope::IO::Writer.from(container: @container, call: @call)
      end
    end
  end
end
