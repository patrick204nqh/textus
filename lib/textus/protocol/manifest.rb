require "yaml"

module Textus
  module Protocol
    Manifest = Data.define(:data, :resolver, :policy)
  end
end

require_relative "manifest/schema"
require_relative "manifest/data"
require_relative "manifest/policy"
require_relative "manifest/resolver"

module Textus
  module Protocol
    class Manifest
      class << self
        def parse(yaml_text, root: ".")
          raw = YAML.safe_load(yaml_text, aliases: true)
          check_version!(raw, "<string>")
          build(raw, root)
        end

        def load(root)
          manifest_path = File.join(root, "manifest.yaml")
          raise IoError.new("manifest not found: #{manifest_path}") unless File.exist?(manifest_path)

          raw = YAML.safe_load_file(manifest_path, aliases: true)
          check_version!(raw, manifest_path)
          build(raw, root)
        end

        private

        def build(raw, root)
          # Phase 1: structural data + authority policy (no entry validation)
          data   = Manifest::Data.parse(raw, root: root)
          policy = Manifest::Policy.new(data)

          policy.entries = data.entries

          new(
            data:,
            resolver: Manifest::Resolver.new(data),
            policy:,
          )
        end

        def check_version!(raw, source)
          return if raw["version"] == PROTOCOL

          raise BadFrontmatter.new(
            source,
            "unsupported manifest version #{raw["version"].inspect}; expected #{PROTOCOL.inspect}",
          )
        end
      end
    end
  end
end

Textus::Manifest = Textus::Protocol::Manifest
