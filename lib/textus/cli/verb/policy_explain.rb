module Textus
  class CLI
    class Verb
      class PolicyExplain < Verb
        def call(store)
          key = positional.shift or raise UsageError.new("policy explain requires a KEY")
          ctx = context_for(store)
          result = Textus::Composition.policy_explain(ctx).call(key: key)
          emit({ "verb" => "policy_explain" }.merge(result.transform_keys(&:to_s)))
        end
      end
    end
  end
end
