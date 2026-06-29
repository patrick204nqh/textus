module Textus
  module Handlers
    module Write
      class PutEntry
        def initialize(container:)
          @container = container
        end

        def call(command, call)
          Textus::Manifest::Data.validate_key!(command.key)
          mentry = @container.manifest.resolver.resolve(command.key).entry

          writer = Store::Entry::Writer.from(container: @container, call: call)
          envelope = writer.put(
            command.key,
            mentry: mentry,
            payload: Textus::Value::Payload.new(
              meta: command.meta,
              body: command.body,
              content: command.content,
            ),
            if_etag: command.if_etag,
          )
          Value::Result.success(envelope)
        end
      end
    end
  end
end
