require "yaml"

module Textus
  # One-shot migration: rewrites the manifest version string from textus/1
  # to textus/2. On-disk entry file shapes are unchanged — the only change
  # needed is the version: line in manifest.yaml.
  module MigrateV2
    def self.run(root)
      manifest_path = File.join(root, "manifest.yaml")
      raise IoError.new("manifest not found: #{manifest_path}") unless File.exist?(manifest_path)

      content = File.read(manifest_path)
      raw = YAML.safe_load(content, aliases: false)

      case raw["version"]
      when PROTOCOL
        { "protocol" => PROTOCOL, "ok" => true, "no_op" => true, "message" => "already #{PROTOCOL}" }
      when "textus/1"
        new_content = content.sub(%r{^version:\s*textus/1\s*$}, "version: #{PROTOCOL}")
        File.write(manifest_path, new_content)
        { "protocol" => PROTOCOL, "ok" => true, "from" => "textus/1", "to" => PROTOCOL }
      else
        raise UsageError.new("cannot migrate from #{raw["version"].inspect}")
      end
    end
  end
end
