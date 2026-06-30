module Textus
  module Handlers
    module Write
      module RejectProposal
        HANDLES = Dispatch::Contracts::RejectProposal
        NEEDS   = %i[file_store manifest schemas audit_log layout event_bus].freeze

        def self.call(command, call, deps)
          mentry = deps.manifest.resolver.resolve(command.pending_key).entry
          unless mentry.in_proposal_lane?(deps.manifest.policy)
            return Value::Result.failure(:proposal_error,
                                         "reject: '#{command.pending_key}' is not in a proposal zone (zone=#{mentry.lane})")
          end

          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          env = reader.read(command.pending_key)
          proposal = env&.meta&.dig("proposal") or
            return Value::Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
          target_key = proposal["target_key"]

          writer = Store::Entry::Writer.new(
            file_store: deps.file_store, manifest: deps.manifest,
            schemas: deps.schemas, audit_log: deps.audit_log,
            call: call, reader: reader, layout: deps.layout
          )
          writer.delete(command.pending_key, mentry: mentry)
          if deps.respond_to?(:event_bus) && deps.event_bus
            deps.event_bus.emit(Textus::Event::ProposalRejected.new(
                                  proposal_key: command.pending_key,
                                  role: call.role,
                                  occurred_at: call.now,
                                ))
          end
          Value::Result.success("protocol" => Textus::PROTOCOL, "rejected" => command.pending_key, "target_key" => target_key)
        end
      end
    end
  end
end
