require "yaml"

module Textus
  module Migrate
    # Hoists per-entry `intake.ttl` / `intake.on_stale` / `intake.sync_budget_ms`
    # into a top-level `policies:` block matched by the entry's exact key, then
    # strips those fields from the entry. After Task 5 the Manifest parser
    # raises on entry-level freshness fields, so this migrator reads/writes the
    # YAML directly without going through the parser.
    #
    # Behavior when a `policies` block with the same `match` already carries a
    # `refresh` rule: skip the hoist for that entry (it's already been
    # migrated). The entry-level fields are left in place so the user can
    # reconcile by hand. This makes the migrator idempotent — a second run
    # produces zero changes on a fully-migrated tree.
    class Policies
      HOISTED_FIELDS = %w[ttl on_stale sync_budget_ms].freeze

      def initialize(root:, dry_run: false)
        @root = root
        @dry_run = dry_run
        @changes = []
      end

      def call
        manifest_path = File.join(@root, ".textus/manifest.yaml")
        return @changes unless File.exist?(manifest_path)

        yaml = YAML.load_file(manifest_path)
        yaml["policies"] ||= []

        Array(yaml["entries"]).each { |e| hoist_entry!(yaml, e) }

        write_manifest!(manifest_path, yaml) if !@dry_run && !@changes.empty?
        @changes
      end

      private

      def hoist_entry!(yaml, entry)
        intake = entry["intake"]
        return unless intake.is_a?(Hash)

        present = HOISTED_FIELDS.select { |f| intake.key?(f) }
        return if present.empty?

        key = entry["key"]
        existing = find_policy_with_refresh(yaml["policies"], key)

        if existing
          @changes << {
            kind: :skip_existing,
            key: key,
            reason: "policy with match=#{key.inspect} already has refresh rule",
          }
          return
        end

        refresh = {}
        present.each { |f| refresh[f] = intake[f] }

        @changes << { kind: :hoist, key: key, refresh: refresh.dup }
        return if @dry_run

        present.each { |f| intake.delete(f) }
        yaml["policies"] << { "match" => key, "refresh" => refresh }
      end

      def find_policy_with_refresh(policies, key)
        Array(policies).find do |p|
          p.is_a?(Hash) && p["match"] == key && p["refresh"].is_a?(Hash)
        end
      end

      def write_manifest!(manifest_path, yaml)
        File.write(manifest_path, yaml.to_yaml)
      end
    end
  end
end
