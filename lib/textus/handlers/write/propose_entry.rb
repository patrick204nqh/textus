module Textus
  module Handlers
    module Write
      module ProposeEntry
        HANDLES = Dispatch::Contracts::ProposeEntry
        NEEDS   = %i[file_store manifest schemas audit_log layout event_bus].freeze

        def self.call(command, call, deps)
          zone = deps.manifest.policy.propose_lane_for(call.role)
          unless zone
            return Value::Result.failure(:propose_forbidden,
                                         "role '#{call.role}' has no writable propose_lane",
                                         details: { "role" => call.role })
          end

          key = "#{zone}.#{command.key}"
          mentry = deps.manifest.resolver.resolve(key).entry
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          writer = Store::Entry::Writer.new(
            file_store: deps.file_store, manifest: deps.manifest,
            schemas: deps.schemas, audit_log: deps.audit_log,
            call: call, reader: reader, layout: deps.layout
          )
          envelope = writer.put(
            key, mentry: mentry,
                 payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content)
          )
          if deps.respond_to?(:event_bus) && deps.event_bus
            deps.event_bus.emit(Textus::Event::EntryWritten.new(
                                  key: key,
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
