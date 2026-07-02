module Textus
  module UseCases
    module Write
      module RejectProposal
        HANDLES = Dispatch::Contracts::RejectProposal
        NEEDS = %i[file_store manifest schemas audit_log layout event_bus writer reader].freeze

        def self.call(command, call, deps)
          mentry = deps.manifest.resolver.resolve(command.pending_key).entry
          unless mentry.in_proposal_lane?(deps.manifest.policy)
            return Value::Result.failure(:proposal_error,
                                         "reject: '#{command.pending_key}' is not in a proposal zone (zone=#{mentry.lane})")
          end

          reader = deps.reader
          env = reader.read(command.pending_key)
          proposal = env&.meta&.dig("proposal") or
            return Value::Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
          target_key = proposal["target_key"]

          writer = deps.writer
          writer.delete(command.pending_key, mentry: mentry, call: call)
          if deps.respond_to?(:event_bus) && deps.event_bus
            deps.event_bus.emit(Textus::Event::ProposalRejected.new(
                                  proposal_key: command.pending_key,
                                  role: call.role,
                                  reason: command.reason,
                                  occurred_at: call.now,
                                ))
          end
          result = { "protocol" => Textus::PROTOCOL, "rejected" => command.pending_key, "target_key" => target_key }
          result["reason"] = command.reason if command.reason
          Value::Result.success(result)
        end
      end
    end
  end
end
