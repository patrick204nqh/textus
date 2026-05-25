module Textus
  class CLI
    class Group
      class Key < Group
        self.cli_name = "key"
        subcommands["mv"]      = Verb::Mv
        subcommands["uid"]     = Verb::Uid
        subcommands["normalize"] = Verb::KeyNormalize
      end
    end
  end
end
