# frozen_string_literal: true

module Textus
  module Action
    class Reject < Base

      verb :reject
      summary "discard a queued proposal without applying it"
      surfaces :cli, :mcp
      cli "reject"
      arg :pending_key, String, required: true, positional: true, description: "the queued proposal's key"

      def self.call(container:, call:, pending_key:)
        mentry = container.manifest.resolver.resolve(pending_key).entry
        unless mentry.in_proposal_lane?(container.manifest.policy)
          raise ProposalError.new("reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.lane})")
        end

        env = container.compositor.read(pending_key)
        parsed = proposal_from(env, key: pending_key)
        target_key = parsed[:target_key]

        mentry = container.manifest.resolver.resolve(pending_key).entry
        container.compositor.delete(pending_key, mentry: mentry, call: call)
        { "protocol" => Textus::PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
      end
    end
  end
end
