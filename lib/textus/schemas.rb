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

    private

    def load_all
      return unless File.directory?(@dir)

      Dir.glob(File.join(@dir, "*.yaml")).each do |path|
        name = File.basename(path, ".yaml")
        @schemas[name] = Schema.load(path)
      end
    end
  end
end
