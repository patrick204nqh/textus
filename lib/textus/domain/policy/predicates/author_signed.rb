# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      module Predicates
        # Predicate: the acting role must hold the 'author' capability in the
        # active manifest (ADR 0030 capability roles). Folds in the old
        # Write::AuthorityGate so accept/reject and rules[].guard share one
        # implementation. No bespoke #error — failures accumulate into
        # GuardFailed (ADR 0031).
        class AuthorSigned
          attr_reader :reason

          def name = "author_signed"

          def call(eval)
            holders = eval.manifest.policy.roles_with_capability("author")
            return true if holders.include?(eval.actor.to_s)

            @reason =
              if holders.empty?
                "no role holds the 'author' capability; #{eval.transition} is disabled"
              else
                "role '#{eval.actor}' lacks the 'author' capability (held by: #{holders.join(", ")})"
              end
            false
          end
        end
      end
    end
  end
end
