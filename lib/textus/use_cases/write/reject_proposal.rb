module Textus
  module UseCases
    module Write
      class RejectProposal < Base
        handles Dispatch::Contracts::RejectProposal
        needs :file_system, :manifest, :audit_log, :layout, :writer, :reader

        def call
          mentry = manifest.resolver.resolve(command.pending_key).entry
          unless mentry.in_proposal_lane?(manifest.policy)
            return failure(:proposal_error,
                           "reject: '#{command.pending_key}' is not in a proposal zone (zone=#{mentry.lane})")
          end

          env = reader.read(command.pending_key)
          proposal = env&.meta&.dig("proposal") or
            return failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
          target_key = proposal["target_key"]

          writer.delete(command.pending_key, mentry: mentry, call: call)
          result = { "protocol" => Textus::PROTOCOL, "rejected" => command.pending_key, "target_key" => target_key }
          result["reason"] = command.reason if command.reason
          success(result)
        end
      end
    end
  end
end
