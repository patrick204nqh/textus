# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module RuleTrace
        HANDLES = Dispatch::Contracts::RuleTrace
        NEEDS = %i[manifest].freeze

        def self.call(command, _call, deps)
          _ruleset, trace = deps.manifest.rules.for_with_trace(command.key)
          Value::Result.success({
                                  "verb" => "rule_trace",
                                  "key" => command.key,
                                  "candidates" => trace.candidates,
                                  "winners" => trace.winners,
                                  "effective" => trace.ruleset_fields,
                                })
        end
      end
    end
  end
end
