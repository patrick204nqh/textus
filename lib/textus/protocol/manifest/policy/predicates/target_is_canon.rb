module Textus
  module Protocol
    class Manifest
      class Policy
        module Predicates
          class TargetIsCanon
            def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
              return { pass: true } if key.nil?

              mentry = manifest.resolver.resolve(key).entry
              pass = mentry.lane.to_s == "knowledge"
              { pass:, reason: pass ? nil : "target lane '#{mentry.lane}' is not knowledge" }
            rescue Textus::UnknownKey
              { pass: true }
            end
          end
        end
      end
    end
  end
end
