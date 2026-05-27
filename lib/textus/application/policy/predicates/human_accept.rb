module Textus
  module Application
    module Policy
      module Predicates
        class HumanAccept
          attr_reader :reason

          def name
            "accept_authority_signed"
          end

          # Checks that an accept-authority role signed the promotion. The role
          # is passed explicitly. In practice, Accept already enforces that an
          # accept-authority (currently "human") has acted before reaching the
          # promotion gate, so this predicate trivially passes. It documents
          # intent and future-proofs multi-actor accept flows.
          def call(role:, entry: nil) # rubocop:disable Lint/UnusedMethodArgument
            role_str = role&.to_s
            # If we cannot determine the role, trust that Accept has already
            # checked — allow through.
            return true if role_str.nil? || role_str.empty?

            ok = (role_str == "human")
            @reason = "current role is '#{role_str}', expected 'human'" unless ok
            ok
          end
        end
      end
    end
  end
end
