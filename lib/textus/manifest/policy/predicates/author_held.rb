module Textus
  class Manifest
    class Policy
      module Predicates
        class AuthorHeld
          def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
            holders = manifest.policy.writers_for("knowledge")
            pass = holders.include?(actor.to_s)
            reason = if pass
                       nil
                     elsif holders.empty?
                       "no role can write knowledge; #{action} is disabled"
                     else
                       "role '#{actor}' cannot write knowledge (held by: #{holders.join(", ")})"
                     end
            { pass:, reason: }
          end
        end
      end
    end
  end
end
