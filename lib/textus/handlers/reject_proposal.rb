module Textus
  module Handlers
    class RejectProposal
      def initialize(compositor:)
        @compositor = compositor
      end

      def call(command, call)
        mentry = @compositor.manifest.resolver.resolve(command.pending_key).entry
        unless mentry.in_proposal_lane?(@compositor.manifest.policy)
          return Result.failure(:proposal_error,
            "reject: '#{command.pending_key}' is not in a proposal zone (zone=#{mentry.lane})")
        end

        env = @compositor.read(command.pending_key)
        proposal = env&.meta&.dig("proposal") or
          return Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
        target_key = proposal["target_key"]

        @compositor.delete(command.pending_key, mentry: mentry, call: call)
        Result.success("protocol" => Textus::PROTOCOL, "rejected" => command.pending_key, "target_key" => target_key)
      end
    end
  end
end
