require "set"

module Textus
  module Bus
    module Predicates
      class AuthorHeld
        def self.call(manifest:, schemas: nil, actor:, action:, key:, envelope: nil, extra: {})
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
