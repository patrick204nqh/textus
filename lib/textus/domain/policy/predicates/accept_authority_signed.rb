module Textus
  module Domain
    module Policy
      module Predicates
        # Promotion predicate: the role driving the promotion must have
        # role_kind == :accept_authority in the active manifest.
        #
        # Accept/Reject already gate on this kind before reaching the
        # promotion policy, so in the default control-flow this predicate
        # trivially passes. It is kept so manifests can express the
        # requirement explicitly in `rules[].promotion.requires`.
        class AcceptAuthoritySigned
          attr_reader :reason

          def name
            "accept_authority_signed"
          end

          def call(role:, manifest:, entry: nil) # rubocop:disable Lint/UnusedMethodArgument
            role_str = role&.to_s
            return true if role_str.nil? || role_str.empty?

            kind = manifest.policy.role_kind(role_str)
            return true if kind == :accept_authority

            @reason = "role '#{role_str}' has kind '#{kind.inspect}', expected ':accept_authority'"
            false
          end
        end
      end
    end
  end
end
