require "yaml"

module Textus
  module Doctor
    class Check
      # Runs as a standalone module (Check::ProtocolVersion.run(root:)) and also
      # as a class-based doctor check (ProtocolVersion.new(store).call).
      class ProtocolVersion < Check
        # Standalone interface: root is the project root (parent of .textus/).
        def self.run(root:)
          path = File.join(root, ".textus/manifest.yaml")
          return [] unless File.exist?(path)

          doc = YAML.safe_load_file(path, aliases: false) || {}
          version = doc["version"]
          return [] if version == "textus/4"

          [{
            "code" => "protocol_mismatch",
            "severity" => "error",
            "message" => "Store reports version=#{version.inspect}; this gem expects textus/4.",
            "hint" => "Upgrade the store's manifest version to textus/4 (see CHANGELOG for breaking changes).",
          }]
        end

        # Doctor check interface: root is the .textus/ directory itself,
        # so manifest.yaml lives directly inside it.
        def call
          path = File.join(root, "manifest.yaml")
          return [] unless File.exist?(path)

          doc = YAML.safe_load_file(path, aliases: false) || {}
          version = doc["version"]
          return [] if version == "textus/4"

          [{
            "code" => "protocol_mismatch",
            "level" => "error",
            "subject" => path,
            "message" => "Store reports version=#{version.inspect}; this gem expects textus/4.",
            "fix" => "Upgrade the store's manifest version to textus/4 (see CHANGELOG for breaking changes).",
          }]
        end
      end
    end
  end
end
