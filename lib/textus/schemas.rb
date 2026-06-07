module Textus
  # Eager-loading schema cache. Loads every *.yaml under +dir+ at construction.
  # A missing directory is treated as "no schemas" (does not raise) to mirror
  # the lazy behavior previously embedded in Store#schema_for.
  class Schemas
    def initialize(dir)
      @dir = dir
      @schemas = {}
      load_all
    end

    def fetch(name)
      @schemas[name] || raise(IoError.new("schema not found: #{File.join(@dir, "#{name}.yaml")}"))
    end

    # Only nil short-circuits. A missing-but-named schema still raises IoError.
    def fetch_or_nil(name)
      return nil if name.nil?

      fetch(name)
    end

    def all
      @schemas.values
    end

    # Name-keyed view: { canonical_name => Schema }. The key is the schema's
    # file stem, which is authoritative even when a schema file carries no
    # top-level `name:` (Schema#name reads the body and may be nil). Symmetric
    # with #all (values); use this when you need the names too.
    def by_name
      @schemas.dup
    end

    private

    def load_all
      return unless File.directory?(@dir)

      Dir.glob(File.join(@dir, "*.yaml")).each do |path|
        name = File.basename(path, ".yaml")
        begin
          @schemas[name] = Schema.load(path)
        rescue StandardError
          # Tolerate broken schema files at construction time so the rest of
          # the store remains loadable. Surfacing the failure is the job of
          # Doctor::Check::SchemaParseError. Lookups via #fetch still raise
          # IoError for the missing-but-named schema.
          next
        end
      end
    end
  end
end
