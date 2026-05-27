module Textus
  module Application
    module Policy
      module Predicates
        class HumanAccept
          attr_reader :reason

          def name
            "accept_authority_signed"
          end

          # Checks that an accept_authority-kind role signed the promotion.
          # Accept's guard already enforces this upstream, so the predicate is
          # effectively documentation today — but it future-proofs multi-actor
          # accept flows and direct callers of Promotion.from_names.
          def call(role:, manifest: nil, entry: nil) # rubocop:disable Lint/UnusedMethodArgument
            role_str = role&.to_s
            return true if role_str.nil? || role_str.empty?

            if manifest
              expected = manifest.roles_with_kind(:accept_authority).first || "human"
              ok = manifest.role_kind(role_str) == :accept_authority
            else
              expected = "human"
              ok = (role_str == expected)
            end
            @reason = "current role is '#{role_str}', expected '#{expected}'" unless ok
            ok
          end
        end
      end
    end
  end
end
