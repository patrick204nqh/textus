module Textus
  class CLI
    class ExtensionGroup < Group
      self.cli_name = "extension"
      subcommands["list"] = Extensions
      subcommands["run"]  = Action
    end
  end
end
