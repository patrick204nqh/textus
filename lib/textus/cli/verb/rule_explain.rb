module Textus
  class CLI
    class Verb
      class RuleExplain < Verb
        command_name "explain"
        parent_group Group::Rule

        def call(store)
          key = positional.shift or raise UsageError.new("policy explain requires a KEY")
          result = session_for(store).policy_explain(key: key)
          emit({ "verb" => "policy_explain" }.merge(result.transform_keys(&:to_s)))
        end
      end
    end
  end
end
