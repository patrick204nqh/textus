module Textus
  module Handlers
    module Write
      module DeleteKey
        HANDLES = Dispatch::Contracts::DeleteKey
        NEEDS   = %i[file_store manifest schemas audit_log layout event_bus].freeze

        def self.call(command, call, deps)
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          writer = Store::Entry::Writer.new(
            file_store: deps.file_store, manifest: deps.manifest,
            schemas: deps.schemas, audit_log: deps.audit_log,
            call: call, reader: reader, layout: deps.layout
          )
          writer.delete(command.key, if_etag: command.if_etag)
          if deps.respond_to?(:event_bus) && deps.event_bus
            deps.event_bus.emit(Textus::Event::EntryDeleted.new(
                                  key: command.key,
                                  role: call.role,
                                  etag_before: nil,
                                  occurred_at: call.now,
                                ))
          end
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "key" => command.key, "deleted" => true)
        end
      end
    end
  end
end
