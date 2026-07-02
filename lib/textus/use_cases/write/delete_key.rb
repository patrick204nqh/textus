module Textus
  module UseCases
    module Write
      module DeleteKey
        HANDLES = Dispatch::Contracts::DeleteKey
        NEEDS = %i[file_store manifest schemas audit_log layout event_bus writer reader].freeze

        def self.call(command, call, deps)
          writer = deps.writer
          writer.delete(command.key, if_etag: command.if_etag, call: call)
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
