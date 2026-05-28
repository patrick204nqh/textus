module Textus
  class CLI
    class Verb
      class RuleLint < Verb
        command_name "lint"
        parent_group Group::Rule

        option :against, "--against=FILE"

        def call(store)
          path = against or raise UsageError.new("rule lint --against=FILE required")
          yaml = File.read(path)
          emit(operations_for(store).rule_lint(candidate_yaml: yaml).to_h)
        end
      end
    end
  end
end
