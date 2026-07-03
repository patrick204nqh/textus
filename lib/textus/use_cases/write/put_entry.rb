module Textus
  module UseCases
    module Write
      class PutEntry < Base
        handles Dispatch::Contracts::PutEntry
        needs :file_system, :manifest, :audit_log, :layout, :writer, :reader

        def call
          writer.put(
            command.key,
            mentry: manifest.resolver.resolve(command.key).entry,
            payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content),
            if_etag: command.if_etag, call: @call
          ).then { |envelope| success(envelope) }
        end
      end
    end
  end
end
