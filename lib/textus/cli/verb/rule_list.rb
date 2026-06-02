module Textus
  class CLI
    class Verb
      class RuleList < Verb
        command_name "list"
        parent_group Group::Rule

        def call(store)
          emit({ "verb" => "rule_list", "policies" => session_for(store).rule_list })
        end
      end
    end
  end
end
