module Textus
  module Handlers
    class PutEntry
      def initialize(compositor:)
        @compositor = compositor
      end

      def call(command, call)
        Textus::Manifest::Data.validate_key!(command.key)
        mentry = @compositor.manifest.resolver.resolve(command.key).entry

        envelope = @compositor.write(
          command.key,
          mentry: mentry,
          payload: Textus::Value::Payload.new(
            meta: command.meta,
            body: command.body,
            content: command.content,
          ),
          call: call,
          if_etag: command.if_etag,
        )
        Result.success(envelope)
      end
    end
  end
end
