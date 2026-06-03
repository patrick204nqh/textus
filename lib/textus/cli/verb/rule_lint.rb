module Textus
  class CLI
    class Verb
      class RuleLint < Runner::Base
        self.spec = Textus::Maintenance::RuleLint.contract
        parent_group Group::Rule

        option :against, "--against=FILE"

        def invoke(store)
          path = against or raise UsageError.new("rule lint --against=FILE required")
          yaml = File.read(path)
          emit(session_for(store).rule_lint(candidate_yaml: yaml).to_h)
        end
      end
    end
  end
end
