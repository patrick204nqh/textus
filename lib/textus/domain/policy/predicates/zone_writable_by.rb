# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      module Predicates
        # Predicate #0 of every write guard. Wraps the post-0.31.0 capability
        # topology gate (role.can ⊇ verb_for(zone.kind)). On failure, #error
        # raises the capability-shaped WriteForbidden so the topology refusal
        # — textus's signature product feature — is unchanged.
        class ZoneWritableBy
          attr_reader :reason

          def name = "zone_writable_by"

          def call(eval)
            manifest = eval.manifest
            @mentry = manifest.resolver.resolve(eval.target).entry
            return true if manifest.policy.permission_for(@mentry.zone.to_s).allows_write?(eval.actor)

            @verb    = manifest.policy.verb_for_zone(@mentry.zone) # capability the kind requires
            @holders = manifest.policy.roles_with_capability(@verb)
            @reason  = "zone '#{@mentry.zone}' needs capability '#{@verb}'; '#{eval.actor}' lacks it"
            false
          end

          # Matches the capability-shaped WriteForbidden landed by ADR 0030
          # Task 3:
          #   WriteForbidden.new(key, zone, verb:, holders:)
          #   → "writing '<k>' (zone '<z>') needs capability '<verb>'",
          #     hint: "held by: <holders>; pass --as=<role>".
          def error(_eval)
            Textus::WriteForbidden.new(@mentry.key, @mentry.zone, verb: @verb, holders: @holders)
          end
        end
      end
    end
  end
end
