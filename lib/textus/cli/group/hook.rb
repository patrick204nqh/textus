module Textus
  class CLI
    class Group
      class Hook < Group
        self.cli_name = "hook"
        subcommands["list"] = Verb::Hooks
        subcommands["run"]  = Verb::HookRun
      end
    end
  end
end
