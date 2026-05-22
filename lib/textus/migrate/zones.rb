require "yaml"
require "fileutils"

module Textus
  module Migrate
    # Renames the four legacy default zones (canon, intake, pending, derived) to
    # their 0.9.2 names (identity, inbox, review, output). Rewrites every entry's
    # `zone` and `path` prefix, moves the on-disk zone directory, and sweeps the
    # leading segment of every `policies[].match` so a `migrate policies` run
    # done first doesn't end up with stale match globs.
    #
    # Operates on the YAML manifest directly via YAML.load_file/File.write so it
    # works on legacy manifests that the current Manifest loader would reject
    # (e.g. one still carrying entry-level `intake.ttl`, which Task 5 made the
    # parser raise on).
    #
    # Idempotent: a second invocation against a fully-migrated tree produces an
    # empty change list and writes nothing.
    class Zones
      RENAMES = {
        "canon" => "identity",
        "intake" => "inbox",
        "pending" => "review",
        "derived" => "output",
      }.freeze

      def initialize(root:, dry_run: false)
        @root = root
        @dry_run = dry_run
        @changes = []
      end

      def call
        manifest_path = File.join(@root, ".textus/manifest.yaml")
        return @changes unless File.exist?(manifest_path)

        yaml = YAML.load_file(manifest_path)

        rename_zones!(yaml)
        rewrite_entries!(yaml)
        sweep_policy_matches!(yaml)

        write_manifest!(manifest_path, yaml) if !@dry_run && !@changes.empty?
        move_zone_dirs! unless @dry_run

        @changes
      end

      private

      def rename_zones!(yaml)
        Array(yaml["zones"]).each do |z|
          new_name = RENAMES[z["name"]]
          next unless new_name

          @changes << { kind: :rename_zone, from: z["name"], to: new_name }
          z["name"] = new_name unless @dry_run
        end
      end

      def rewrite_entries!(yaml)
        Array(yaml["entries"]).each do |e|
          old_zone = e["zone"]
          new_zone = RENAMES[old_zone]
          next unless new_zone

          @changes << {
            kind: :rewrite_entry,
            key: e["key"],
            zone_from: old_zone,
            zone_to: new_zone,
          }
          next if @dry_run

          e["zone"] = new_zone
          e["path"] = e["path"].sub(%r{\A#{Regexp.escape(old_zone)}/}, "#{new_zone}/") if e["path"].is_a?(String)
        end
      end

      def sweep_policy_matches!(yaml)
        Array(yaml["policies"]).each do |p|
          match = p["match"]
          next unless match.is_a?(String)

          segments = match.split(".")
          new_first = RENAMES[segments.first]
          next unless new_first

          old_match = match
          segments[0] = new_first
          new_match = segments.join(".")
          @changes << {
            kind: :rewrite_policy_match,
            match_from: old_match,
            match_to: new_match,
          }
          p["match"] = new_match unless @dry_run
        end
      end

      def write_manifest!(manifest_path, yaml)
        File.write(manifest_path, yaml.to_yaml)
      end

      def move_zone_dirs!
        RENAMES.each do |old, new_n|
          old_dir = File.join(@root, ".textus/zones", old)
          new_dir = File.join(@root, ".textus/zones", new_n)
          next unless Dir.exist?(old_dir)

          if Dir.exist?(new_dir)
            # New dir already exists (idempotent re-run or partial state). Skip
            # the move; the rename step won't have added a change either.
            next
          end

          FileUtils.mv(old_dir, new_dir)
          @changes << { kind: :move_dir, from: old_dir, to: new_dir }
        end
      end
    end
  end
end
