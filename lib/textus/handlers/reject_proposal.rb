module Textus
  module Handlers
    class RejectProposal
      def initialize(container:)
        @container = container
      end

      def call(command, call)
        mentry = @container.manifest.resolver.resolve(command.pending_key).entry
        unless mentry.in_proposal_lane?(@container.manifest.policy)
          return Value::Result.failure(:proposal_error,
                                       "reject: '#{command.pending_key}' is not in a proposal zone (zone=#{mentry.lane})")
        end

        env = @container.pipeline.read(command.pending_key)
        proposal = env&.meta&.dig("proposal") or
          return Value::Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
        target_key = proposal["target_key"]

        @container.pipeline.delete(command.pending_key, mentry: mentry, call: call)
        Value::Result.success("protocol" => Textus::PROTOCOL, "rejected" => command.pending_key, "target_key" => target_key)
      end
    end
  end
end
