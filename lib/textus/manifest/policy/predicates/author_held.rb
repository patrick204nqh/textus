module Textus
  class Manifest
    class Policy
      module Predicates
        class AuthorHeld
          def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
            holders = manifest.policy.roles_with_capability("author")
            pass = holders.include?(actor.to_s)
            reason = if pass
                       nil
                     elsif holders.empty?
                       "no role holds the 'author' capability; #{action} is disabled"
                     else
                       "role '#{actor}' lacks the 'author' capability (held by: #{holders.join(", ")})"
                     end
            { pass:, reason: }
          end
        end
      end
    end
  end
end
