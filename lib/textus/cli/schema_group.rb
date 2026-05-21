module Textus
  class CLI
    class SchemaGroup < Group
      self.cli_name = "schema"
      subcommands["show"]    = SchemaVerb
      subcommands["init"]    = SchemaInit
      subcommands["diff"]    = SchemaDiff
      subcommands["migrate"] = SchemaMigrate
    end
  end
end
