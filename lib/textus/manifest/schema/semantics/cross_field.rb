module Textus
  class Manifest
    module Schema
      module Semantics
        module CrossField
          def check_cross_field!(raw)
            check_owners!(raw["lanes"], raw["entries"])
            check_lane_kind_consistency!(raw)
          end

          def check_owners!(lanes, entries)
            Array(lanes).each_with_index { |z, i| check_owner!(z["owner"], "$.lanes[#{i}]") }
            Array(entries).each_with_index { |e, i| check_owner!(e["owner"], "$.entries[#{i}]") }
          end

          def check_owner!(owner, path)
            return if owner.nil?
            return if valid_owner?(owner)

            raise BadManifest.new(
              "invalid owner '#{owner}' at '#{path}' " \
              "(expected <archetype> or <archetype>:<subject>, archetype one of: #{Textus::Value::Role::NAMES.join(", ")})",
            )
          end

          def valid_owner?(token)
            return false unless token.is_a?(String) && !token.empty?

            archetype, subject = token.split(":", 2)
            return false unless Textus::Value::Role::NAMES.include?(archetype)
            return true if subject.nil?

            OWNER_SUBJECT_PATTERN.match?(subject)
          end

          def check_lane_kind_consistency!(raw)
            held = Capabilities.resolve(raw["roles"]).values.flatten.uniq

            Array(raw["lanes"]).each_with_index do |z, i|
              verb = KIND_REQUIRES_VERB[z["kind"]]
              next if verb.nil? || held.include?(verb)

              raise BadManifest.new(
                "lane '#{z["name"]}' (#{z["kind"]}) at '$.lanes[#{i}]' " \
                "needs a role with capability '#{verb}'; none declared",
              )
            end
          end
        end
      end
    end
  end
end
