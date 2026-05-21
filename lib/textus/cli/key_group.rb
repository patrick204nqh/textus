module Textus
  class CLI
    class KeyGroup < Group
      self.cli_name = "key"
      subcommands["mv"]      = Mv
      subcommands["uid"]     = Uid
      subcommands["migrate"] = MigrateKeysVerb
    end
  end
end
