module Textus
  module Bus
    module Predicates
      class LaneWritableBy
        def initialize(manifest)
          @manifest = manifest
        end

        def call(command, call)
          key = extract_key(command)
          return unless key

          mentry = resolve_entry(key)
          lane_verb = @manifest.policy.verb_for_lane(mentry.lane.to_s)
          caps = @manifest.data.role_caps.fetch(call.role, [])

          return if caps.include?(lane_verb.to_s)

          holders = @manifest.policy.roles_with_capability(lane_verb.to_s)
          raise Textus::WriteForbidden.new(mentry.key, mentry.lane, verb: lane_verb, holders: holders)
        end

        private

        def extract_key(command)
          command.respond_to?(:key) ? command.key : command.respond_to?(:old_key) ? command.old_key : nil
        end

        def resolve_entry(key)
          @manifest.resolver.resolve(key).entry
        rescue Textus::UnknownKey
          nil
        end
      end
    end
  end
end
