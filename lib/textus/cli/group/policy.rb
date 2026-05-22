module Textus
  class CLI
    class Group
      class Policy < Group
        self.cli_name = "policy"
        subcommands["list"]    = Verb::PolicyList
        subcommands["explain"] = Verb::PolicyExplain
      end
    end
  end
end
