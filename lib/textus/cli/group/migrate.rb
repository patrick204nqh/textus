module Textus
  class CLI
    class Group
      class Migrate < Group
        self.cli_name = "migrate"
        subcommands["zones"]    = Verb::MigrateZones
        subcommands["policies"] = Verb::MigratePolicies

        # Every subcommand under `migrate` operates on the on-disk YAML
        # manifest directly (legacy shapes the Manifest parser would reject),
        # so the CLI must NOT eagerly build a Store before dispatching.
        def self.needs_store? = false
      end
    end
  end
end
