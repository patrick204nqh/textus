module Textus
  class Store
    class Geometry
      RUN    = ".state"
      DATA   = "data"
      ASSETS = "assets"

      def initialize(root)
        @root = root
        freeze
      end

      attr_reader :root

      # -- data paths --
      def data_root = File.join(@root, DATA)
      def lane_path(lane_name) = File.join(data_root, lane_name.to_s)

      def entry_path(mentry)
        primary_ext = Format.for(mentry.format).extensions.first
        rel = normalize_relative_path(mentry.path)
        if File.extname(mentry.path) == ""
          File.join(@root, rel + primary_ext)
        else
          File.join(@root, rel)
        end
      end

      # -- runtime paths --
      def run_root           = File.join(@root, RUN)
      def cursor_path(role)  = File.join(run_root, "ephemeral", "cursors", role.to_s)
      def lock_path(name)    = File.join(run_root, "ephemeral", "locks", "#{name}.lock")
      def audit_dir_path     = File.join(run_root, "audit")
      def audit_log_path     = File.join(audit_dir_path, "audit.log")
      def sentinels_root = File.join(run_root, "tracking", "sentinels")
      def store_db_path = File.join(run_root, "store.db")

      # -- asset paths --
      def asset_path(kind, date_str, zone, filename)
        File.join(@root, ASSETS, kind, date_str, zone.to_s, filename)
      end

      # -- config paths --
      def manifest_path = File.join(@root, "manifest.yaml")
      def schemas_dir = File.join(@root, "schemas")
      def schema_path(name) = File.join(schemas_dir, "#{name}.yaml")
      def template_path(name) = File.join(@root, "templates", name)
      def workflow_dir     = File.join(@root, "workflows")
      def hooks_dir        = File.join(@root, "hooks")
      def schemas_glob     = File.join(schemas_dir, "**", "*")

      # -- gitignore --
      def gitignore_body(untracked_entries: [])
        lines = ["# textus runtime artifacts — safe to delete, never commit",
                 "#{RUN}/"]
        unless untracked_entries.empty?
          lines << "# tracked:false entries — protocol-readable, not committed"
          lines.concat(untracked_entries)
        end
        "#{lines.join("\n")}\n"
      end

      # -- lane boundary (replaces Writer#zone_floor) --
      def lane_floor(path)
        prefix = "#{data_root}/"
        return nil unless path.start_with?(prefix)

        seg = path.delete_prefix(prefix).split("/").first
        seg && File.join(data_root, seg)
      end

      private

      def normalize_relative_path(path)
        return path if path.start_with?("data/")

        File.join("data", path)
      end
    end
  end
end
