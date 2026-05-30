module Textus
  module Write
    # Shared gate for write verbs that require the caller to hold the
    # manifest's accept capability. Provides one method, expressed as two
    # early-returns rather than a ternary, so each failure mode reads on its
    # own line.
    module AuthorityGate
      def assert_accept_authority!(verb)
        return if @manifest.policy.roles_with_capability("accept").include?(@call.role.to_s)

        authority = @manifest.policy.roles_with_capability("accept").first
        if authority.nil?
          raise ProposalError.new(
            "no role holds the accept capability in this manifest; #{verb} is disabled",
          )
        end

        raise ProposalError.new(
          "only #{authority} role can #{verb} proposals; got '#{@call.role}'",
        )
      end
    end
  end
end
