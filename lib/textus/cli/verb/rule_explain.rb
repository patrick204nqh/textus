module Textus
  class CLI
    class Verb
      class RuleExplain < Verb
        def call(store)
          key = positional.shift or raise UsageError.new("policy explain requires a KEY")
          result = operations_for(store).reads.policy_explain.call(key: key)
          emit({ "verb" => "policy_explain" }.merge(result.transform_keys(&:to_s)))
        end
      end
    end
  end
end
