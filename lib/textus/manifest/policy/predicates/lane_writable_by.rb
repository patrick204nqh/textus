module Textus
  class Manifest
    class Policy
      module Predicates
        class LaneWritableBy
          def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
            return { pass: true } if key.nil?

            mentry = manifest.resolver.resolve(key).entry
            lane_verb = manifest.policy.verb_for_lane(mentry.lane.to_s)
            caps = Set.new(manifest.data.role_caps.fetch(actor.to_s, []))
            return { pass: true } if caps.include?(lane_verb.to_s)

            holders = manifest.policy.roles_with_capability(lane_verb.to_s)
            { pass: false, error: Textus::WriteForbidden.new(mentry.key, mentry.lane, verb: lane_verb, holders:) }
          rescue Textus::UnknownKey
            { pass: true }
          end
        end
      end
    end
  end
end
