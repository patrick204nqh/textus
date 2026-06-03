require "yaml"

module Textus
  module Maintenance
    # Compare the live manifest's `rules:` block against a candidate
    # YAML string. Returns a Plan describing rule additions/removals/
    # changes. Does NOT write anything.
    class RuleLint
      extend Textus::Contract::DSL

      verb     :rule_lint
      summary  "Diff candidate manifest YAML's rules against the live manifest. No writes."
      surfaces :cli, :mcp
      cli      "rule lint"
      arg :candidate_yaml, String, required: true, wire_name: :against, source: :file,
                                   description: "path to candidate manifest YAML; its `rules:` block is diffed against the live manifest"
      view { |v, _i| v.to_h }

      def initialize(container:, call:)
        @container = container
        @call      = call
        @root      = container.root
      end

      def call(candidate_yaml:)
        live_rules      = current_rules
        candidate_rules = parse_candidate(candidate_yaml)

        live_by_match      = live_rules.to_h { |r| [r["match"], r] }
        candidate_by_match = candidate_rules.to_h { |r| [r["match"], r] }

        steps = (candidate_by_match.keys - live_by_match.keys).map do |m|
          { "op" => "add_rule", "match" => m, "rule" => candidate_by_match[m] }
        end
        (live_by_match.keys - candidate_by_match.keys).each do |m|
          steps << { "op" => "remove_rule", "match" => m }
        end
        (live_by_match.keys & candidate_by_match.keys).each do |m|
          next if live_by_match[m] == candidate_by_match[m]

          steps << { "op" => "change_rule", "match" => m,
                     "from" => live_by_match[m], "to" => candidate_by_match[m] }
        end

        Plan.new(steps: steps, warnings: [])
      end

      private

      def current_rules
        raw = YAML.safe_load_file(File.join(@root, "manifest.yaml"),
                                  permitted_classes: [Symbol], aliases: false)
        Array(raw["rules"])
      end

      def parse_candidate(yaml_text)
        raw = YAML.safe_load(yaml_text, permitted_classes: [Symbol], aliases: false)
        raise UsageError.new("candidate is not a YAML mapping") unless raw.is_a?(Hash)

        Array(raw["rules"])
      rescue Psych::Exception => e
        raise UsageError.new("candidate YAML parse error: #{e.message}")
      end
    end
  end
end
