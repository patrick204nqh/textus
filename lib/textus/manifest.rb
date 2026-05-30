require "yaml"

module Textus
  # Manifest is the composition record for a parsed manifest. It bundles
  # four collaborators:
  #
  #   * data     — frozen value: raw, root, zones, entries, audit_config, role_mapping
  #   * resolver — resolves keys → entry + path
  #   * policy   — zone/role authority (zone_writers, declared_kind/derived_zone?/
  #     queue_zone?, permission_for, …)
  #   * rules    — match-block rule engine (refresh, handler allowlist, promotion, …)
  #
  # Use `manifest.data.entries`, `manifest.policy.declared_kind(z)`, etc.
  Manifest = Data.define(:data, :resolver, :policy, :rules)
end

require_relative "manifest/schema"
require_relative "manifest/data"
require_relative "manifest/policy"
require_relative "manifest/resolver"
require_relative "manifest/capabilities"

# Reopen Textus::Manifest (defined above as a Data.define) to attach
# class-level loaders and helpers.
module Textus # rubocop:disable Style/OneClassPerFile
  class Manifest
    class << self
      def parse(yaml_text, root: ".")
        raw = YAML.safe_load(yaml_text, aliases: false)
        check_version!(raw, "<string>")
        build(raw, root)
      end

      def load(root)
        manifest_path = File.join(root, "manifest.yaml")
        raise IoError.new("manifest not found: #{manifest_path}") unless File.exist?(manifest_path)

        raw = YAML.safe_load_file(manifest_path, aliases: false)
        check_version!(raw, manifest_path)
        build(raw, root)
      end

      private

      def build(raw, root)
        data = Manifest::Data.parse(raw, root: root)
        new(
          data: data,
          resolver: Manifest::Resolver.new(data),
          policy: data.policy,
          rules: Manifest::Rules.parse(raw["rules"] || []),
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
