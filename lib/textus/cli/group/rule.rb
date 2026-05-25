module Textus
  class CLI
    class Group
      class Rule < Group
        self.cli_name = "rule"
        subcommands["list"]    = Verb::RuleList
        subcommands["explain"] = Verb::RuleExplain
      end
    end
  end
end
