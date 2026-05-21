module Textus
  class CLI
    class HookGroup < Group
      self.cli_name = "hook"
      subcommands["list"] = Hooks
      subcommands["run"]  = Action
    end
  end
end
