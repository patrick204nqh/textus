module Textus
  module UseCases
    module Write
      module PutEntry
        HANDLES = Dispatch::Contracts::PutEntry
        NEEDS = %i[file_store manifest schemas audit_log layout event_bus].freeze

        def self.call(command, call, deps)
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          writer = Store::Entry::Writer.new(
            file_store: deps.file_store, manifest: deps.manifest,
            schemas: deps.schemas, audit_log: deps.audit_log,
            call: call, reader: reader, layout: deps.layout
          )
          envelope = writer.put(
            command.key,
            mentry: deps.manifest.resolver.resolve(command.key).entry,
            payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content),
            if_etag: command.if_etag,
          )
          if deps.respond_to?(:event_bus) && deps.event_bus
            deps.event_bus.emit(Textus::Event::EntryWritten.new(
                                  key: command.key,
                                  role: call.role,
                                  etag_before: nil,
                                  etag_after: envelope.etag,
                                  occurred_at: call.now,
                                ))
          end
          Value::Result.success(envelope)
        end
      end
    end
  end
end
