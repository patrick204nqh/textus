# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      module Predicates
        # Predicate: a proposal may only target a `canon` zone (ADR 0035). Runs
        # on the `accept` floor, where Evaluation#target is the proposal's
        # resolved target_key. Refuses promotion into workspace/derived/
        # quarantine/queue — the queue→canon path is the only coherent one.
        # No bespoke #error; failures accumulate into GuardFailed (ADR 0031).
        class TargetIsCanon
          attr_reader :reason

          def name = "target_is_canon"

          def call(eval)
            zone = eval.manifest.resolver.resolve(eval.target).entry.zone
            kind = eval.manifest.policy.declared_kind(zone.to_s)
            return true if kind == :canon

            @reason = "proposal target '#{eval.target}' is in zone '#{zone}' " \
                      "(kind: #{kind || "none"}); proposals may only target a canon zone"
            false
          rescue Textus::UnknownKey
            @reason = "proposal target '#{eval.target}' resolves to no declared entry"
            false
          end
        end
      end
    end
  end
end
