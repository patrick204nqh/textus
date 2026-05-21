module Textus
  class CLI
    class Group
      class Schema < Group
        self.cli_name = "schema"
        subcommands["show"]    = Verb::Schema
        subcommands["init"]    = Verb::SchemaInit
        subcommands["diff"]    = Verb::SchemaDiff
        subcommands["migrate"] = Verb::SchemaMigrate
      end
    end
  end
end
