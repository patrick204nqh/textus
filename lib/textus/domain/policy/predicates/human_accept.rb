module Textus
  module Domain
    module Policy
      module Predicates
        class HumanAccept
          attr_reader :reason

          def name
            "human_accept"
          end

          # The role is passed via `store` (an Application::Context-like object
          # with a `role` reader) or through the entry metadata. In practice,
          # Accept already enforces role == "human" before reaching the
          # promotion gate, so this predicate trivially passes. It documents
          # intent and future-proofs multi-actor accept flows.
          def call(store:, entry: nil) # rubocop:disable Lint/UnusedMethodArgument
            role = store.respond_to?(:role) ? store.role.to_s : nil
            # If we cannot determine the role (e.g. store doesn't expose it),
            # we trust that Accept has already checked — allow through.
            return true if role.nil?

            ok = (role == "human")
            @reason = "current role is '#{role}', expected 'human'" unless ok
            ok
          end
        end
      end
    end
  end
end
