module Textus
  class CLI
    class Verb
      class PolicyExplain < Verb
        def call(store)
          key = positional.shift or raise UsageError.new("policy explain requires a KEY")
          role = Role.resolve(flag: nil, env: ENV, root: store.root)
          ctx = Textus::Composition.context(store, role: role)
          result = Textus::Composition.policy_explain(ctx).call(key: key)
          emit({ "verb" => "policy_explain" }.merge(result.transform_keys(&:to_s)))
        end
      end
    end
  end
end
