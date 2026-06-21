# frozen_string_literal: true

require "yaml"

module Textus
  module Action
    class RuleLint < Base
      extend Textus::Contract::DSL

      verb :rule_lint
      summary "Diff candidate manifest YAML's rules against the live manifest. No writes."
      surfaces :cli, :mcp
      cli "rule lint"
      arg :candidate_yaml, String, required: true, wire_name: :against, source: :file,
                                   description: "path to candidate manifest YAML; its `rules:` block is diffed against the live manifest"
      view { |v, _i| v.to_h }

      def self.call(container:, call:, candidate_yaml:)
        root = container.root
        live_rules = current_rules(root)
        candidate_rules = parse_candidate(candidate_yaml)

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

          steps << {
            "op" => "change_rule",
            "match" => match,
            "from" => live_by_match[match],
            "to" => candidate_by_match[match],
          }
        end

        Textus::Store::Jobs::Plan.new(steps: steps, warnings: [])
      end

      def self.current_rules(root)
        raw = YAML.safe_load_file(File.join(root, "manifest.yaml"), permitted_classes: [Symbol], aliases: false)
        Array(raw["rules"])
      end

      def self.parse_candidate(yaml_text)
        raw = YAML.safe_load(yaml_text, permitted_classes: [Symbol], aliases: false)
        raise UsageError.new("candidate is not a YAML mapping") unless raw.is_a?(Hash)

        Array(raw["rules"])
      rescue Psych::Exception => e
        raise UsageError.new("candidate YAML parse error: #{e.message}")
      end
    end
  end
end
