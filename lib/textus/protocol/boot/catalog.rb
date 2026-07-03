module Textus
  module Protocol
    module Boot
      module Catalog
        CURATED_CLI_VERBS = [
          { "name" => "boot" },
          { "name" => "list" },
          { "name" => "get" },
          { "name" => "ingest" },
          { "name" => "where" },
          { "name" => "schema", "summary" => "schema operations: 'schema show KEY', 'schema diff', 'schema init', 'schema migrate'" },
          { "name" => "put" },
          { "name" => "propose" },
          { "name" => "accept" },
          { "name" => "key", "summary" => "key operations: 'key delete', 'key mv', 'key uid'" },
          { "name" => "drain" },
          { "name" => "audit" },
          { "name" => "blame" },
          { "name" => "pulse" },
        ].freeze

        def self.build
          summaries = Textus::VerbRegistry.registered.to_h { |s| [s.verb.to_s, s.summary] }
          CURATED_CLI_VERBS.map do |entry|
            derived = summaries[entry["name"]]
            derived ? entry.merge("summary" => derived) : entry
          end
        end
      end
    end
  end
end
