# frozen_string_literal: true

require "yaml"

module Textus
  module UseCases
    module Ops
      module RuleLint
        HANDLES = Dispatch::Contracts::RuleLint
        NEEDS = %i[manifest].freeze

        def self.call(command, _call, deps)
          root = deps.manifest.data.root
          live_rules = current_rules(root)
          candidate_result = parse_candidate(command.candidate_yaml)
          return candidate_result if candidate_result.is_a?(Value::Result) && candidate_result.failure?

          candidate_rules = candidate_result
          live_by_match = live_rules.to_h { |rule| [rule["match"], rule] }
          candidate_by_match = candidate_rules.to_h { |rule| [rule["match"], rule] }

          steps = (candidate_by_match.keys - live_by_match.keys).map do |match|
            { "op" => "add_rule", "match" => match, "rule" => candidate_by_match[match] }
          end
          (live_by_match.keys - candidate_by_match.keys).each do |match|
            steps << { "op" => "remove_rule", "match" => match }
          end
          (live_by_match.keys & candidate_by_match.keys).each do |match|
            next if live_by_match[match] == candidate_by_match[match]

            steps << { "op" => "change_rule", "match" => match, "from" => live_by_match[match], "to" => candidate_by_match[match] }
          end

          Value::Result.success(Textus::Store::Jobs::Plan.new(steps: steps, warnings: []))
        end

        def self.current_rules(root)
          raw = YAML.safe_load_file(File.join(root, "manifest.yaml"), permitted_classes: [Symbol], aliases: false)
          Array(raw["rules"])
        end

        def self.parse_candidate(yaml_text)
          raw = YAML.safe_load(yaml_text, permitted_classes: [Symbol], aliases: false)
          return Value::Result.failure(:usage_error, "candidate is not a YAML mapping") unless raw.is_a?(Hash)

          Array(raw["rules"])
        rescue Psych::Exception => e
          Value::Result.failure(:usage_error, "candidate YAML parse error: #{e.message}")
        end
      end
    end
  end
end
