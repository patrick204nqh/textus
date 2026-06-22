module Textus
  module Bus
    module Predicates
      class TargetIsCanon
        def self.call(manifest:, schemas: nil, actor:, action:, key:, envelope: nil, extra: {})
          return { pass: true } if key.nil?

          mentry = manifest.resolver.resolve(key).entry
          kind = manifest.policy.declared_kind(mentry.lane.to_s)
          pass = kind == :canon
          { pass:, reason: pass ? nil : "target lane '#{mentry.lane}' is not canon (kind: #{kind})" }
        rescue Textus::UnknownKey
          { pass: true }
        end
      end
    end
  end
end
