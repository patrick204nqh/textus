module Textus
  class CLI
    class Verb
      class RuleExplain < Verb
        command_name "explain"
        parent_group Group::Rule

        option :detail, "--detail"

        def call(store)
          key = positional.shift or raise UsageError.new("rule explain requires a KEY")
          result = session_for(store).rule_explain(key, detail: detail || false)
          emit({ "verb" => "rule_explain" }.merge(result.transform_keys(&:to_s)))
        end
      end
    end
  end
end
