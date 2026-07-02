module Textus
  class Manifest
    class Policy
      module Predicates
        class LaneWritableBy
          def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
            return { pass: true } if key.nil?

            mentry = manifest.resolver.resolve(key).entry
            writers = manifest.policy.writers_for(mentry.lane.to_s)
            return { pass: true } if writers.include?(actor.to_s)

            { pass: false, error: Textus::WriteForbidden.new(mentry.key, mentry.lane, holders: writers) }
          rescue Textus::UnknownKey
            { pass: true }
          end
        end
      end
    end
  end
end
