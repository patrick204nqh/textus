require "yaml"

module Textus
  # Manifest is the composition record for a parsed manifest. It bundles
  # four collaborators:
  #
  #   * data     — frozen value: raw, root, zones, entries, audit_config, role_mapping
  #   * resolver — resolves keys → entry + path
  #   * policy   — zone/role authority (zone_writers, zone_kinds, permission_for, …)
  #   * rules    — match-block rule engine (refresh, handler allowlist, promotion, …)
  #
  # Use `manifest.data.entries`, `manifest.policy.zone_kinds(z)`, etc.
  # The flat accessors on Manifest itself (zones, entries, zone_writers, …)
  # are deprecation shims; they emit a warning and will be removed in 0.26.0.
  Manifest = Data.define(:data, :resolver, :policy, :rules)
end

require_relative "manifest/schema"
require_relative "manifest/data"
require_relative "manifest/policy"
require_relative "manifest/resolver"
require_relative "manifest/role_kinds"

# Reopen Textus::Manifest (defined above as a Data.define) to attach
# class-level loaders, the deprecation shims, and helpers.
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

      def __deprecation_warn(method_name, child, target)
        msg = if child
                "[textus] Manifest##{method_name} is deprecated in 0.25.1; use manifest.#{child}.#{target}"
              else
                "[textus] Manifest##{method_name} is deprecated in 0.25.1; route through manifest.data/policy/resolver/rules"
              end
        warn(msg)
      end

      private

      def build(raw, root)
        data = Manifest::Data.parse(raw, root: root)
        composition = new(
          data: data,
          resolver: Manifest::Resolver.new(data),
          policy: data.policy,
          rules: Manifest::Rules.parse(raw["rules"] || []),
        )
        # Re-point entries' back-reference from Data to the composition
        # record. Entries call `@manifest.policy.*` / `@manifest.resolver.*`
        # at use time (see Entry::Base, Entry::Nested).
        data.entries.each { |e| e.instance_variable_set(:@manifest, composition) }
        composition
      end

      def check_version!(raw, source)
        return if raw["version"] == PROTOCOL

        raise BadFrontmatter.new(
          source,
          "unsupported manifest version #{raw["version"].inspect}; expected #{PROTOCOL.inspect}",
        )
      end
    end

    # --- Deprecation shims (removed in 0.26.0) -------------------------------
    # Internal callers in lib/ have been migrated to the new homes
    # (manifest.data.*, manifest.policy.*, manifest.rules.for(k)). These
    # shims keep user-facing surfaces (hooks DSL, doctor callbacks, MCP)
    # working while we migrate them in subsequent tasks.

    DEPRECATED = {
      # name => [child, target_method]
      zones: %i[data zones],
      zone_readers: %i[data zone_readers],
      audit_config: %i[data audit_config],
      entries: %i[data entries],
      raw: %i[data raw],
      root: %i[data root],
      role_mapping: %i[policy role_mapping],
      role_kind: %i[policy role_kind],
      roles_with_kind: %i[policy roles_with_kind],
      zone_writers: %i[policy zone_writers],
      zone_kinds: %i[policy zone_kinds],
      permission_for: %i[policy permission_for],
    }.freeze

    DEPRECATED.each do |name, (child, target)|
      define_method(name) do |*args, **kwargs, &blk|
        Manifest.__deprecation_warn(name, child, target)
        public_send(child).public_send(target, *args, **kwargs, &blk)
      end
    end

    def rules_for(key)
      Manifest.__deprecation_warn(:rules_for, :rules, :for)
      rules.for(key)
    end

    def validate_key!(key)
      Manifest.__deprecation_warn(:validate_key!, nil, nil)
      Manifest::Data.validate_key!(key)
    end
  end
end
