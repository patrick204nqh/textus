module Textus
  module Protocol
    class Schema
      class Registry
        def initialize(dir)
          @dir = dir
          @schemas = {}
          load_all
        end

        def fetch(name)
          @schemas[name] || raise(Textus::IoError.new("schema not found: #{File.join(@dir, "#{name}.yaml")}"))
        end

        def fetch_or_nil(name)
          return nil if name.nil?

          fetch(name)
        end

        def all
          @schemas.values
        end

        def by_name
          @schemas.dup
        end

        private

        def load_all
          return unless File.directory?(@dir)

          Dir.glob(File.join(@dir, "*.yaml")).each do |path|
            name = File.basename(path, ".yaml")
            @schemas[name] = Textus::Protocol::Schema.load(path)
          rescue StandardError => e
            warn "textus: failed to load schema '#{name}' at #{path}: #{e.message}"
          end
        end
      end
    end
  end
end
