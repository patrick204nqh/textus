module Textus
  class Manifest
    class Policy
      module Predicates
        class LaneDeletableBy
          def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
            return { pass: true } if key.nil?

            mentry = manifest.resolver.resolve(key).entry
            is_raw = manifest.policy.declared_kind(mentry.lane.to_s) == :raw
            lane_verb = manifest.policy.verb_for_lane(mentry.lane.to_s)
            caps = Set.new(manifest.data.role_caps.fetch(actor.to_s, []))

            pass = if is_raw
                     caps.include?("author")
                   else
                     caps.include?(lane_verb.to_s) || caps.include?("author")
                   end
            return { pass: true } if pass

            extra_holders = is_raw ? ["author"] : [lane_verb.to_s, "author"]
            holders = extra_holders.flat_map { |v| manifest.policy.roles_with_capability(v) }.uniq
            { pass: false, error: Textus::WriteForbidden.new(mentry.key, mentry.lane, verb: lane_verb, holders:) }
          rescue Textus::UnknownKey
            { pass: true }
          end
        end
      end
    end
  end
end
