module Textus
  module Domain
    module Policy
      module Predicates
        # Promotion predicate: the role driving the promotion must hold the
        # 'accept' capability in the active manifest.
        #
        # Accept/Reject already gate on the accept capability before reaching
        # the promotion policy, so in the default control-flow this predicate
        # trivially passes. It is kept so manifests can express the
        # requirement explicitly in `rules[].promotion.requires`.
        class AcceptSigned
          attr_reader :reason

          def name
            "accept_signed"
          end

          def call(role:, manifest:, entry: nil) # rubocop:disable Lint/UnusedMethodArgument
            role_str = role&.to_s
            return true if role_str.nil? || role_str.empty?

            return true if manifest.policy.roles_with_capability("accept").include?(role_str)

            @reason = "role '#{role_str}' does not hold the 'accept' capability"
            false
          end
        end
      end
    end
  end
end
