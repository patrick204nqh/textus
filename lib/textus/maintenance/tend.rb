require "fileutils"

module Textus
  module Maintenance
    # The destructive-only lifecycle sweep (ADR 0079, supersedes the composite
    # 0078 body). Drives off the unified Domain::Lifecycle reporter: it applies
    # destructive actions a read never performs (drop = delete via Write::Delete;
    # archive = copy to <store>/archive/ then delete) and refreshes cold expired
    # intake entries (on_expire: refresh) via Write::FetchWorker. Non-destructive
    # annotation (warn) is left to the lazy `get`/`freshness` path. Adds no new
    # authority — every sub-op runs with the CALLER's own `call` (role), and is
    # gated exactly as on its own.
    class Tend
      extend Textus::Contract::DSL

      verb     :tend
      summary  "Run the destructive lifecycle sweep: drop/archive expired entries, refresh cold intake, report health."
      surfaces :cli, :mcp
      cli      "tend"
      arg :prefix,  String, description: "restrict the sweep to keys under this dotted prefix"
      arg :zone,    String, description: "restrict the sweep to entries in this zone"
      arg :dry_run, :boolean, default: false,
                              description: "when true, report what the sweep WOULD do without applying; " \
                                           "defaults to false, so omitting it drops/archives/refreshes immediately"

      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call(prefix: nil, zone: nil, dry_run: false)
        rows = Textus::Domain::Lifecycle.new(
          manifest: @container.manifest,
          file_stat: Textus::Ports::Storage::FileStat.new,
          clock: Textus::Ports::Clock,
        ).call(prefix: prefix, zone: zone)

        health = Read::Doctor.new(container: @container, call: @call).call
        return dry_run_result(rows, health) if dry_run

        apply_result(apply(rows), health)
      end

      private

      def dry_run_result(rows, health)
        {
          "protocol" => Textus::PROTOCOL, "ok" => true, "dry_run" => true,
          "would_drop" => action_keys(rows, "drop"),
          "would_archive" => action_keys(rows, "archive"),
          "would_refresh" => action_keys(rows, "refresh"),
          "health" => health
        }
      end

      def apply_result(result, health)
        {
          "protocol" => Textus::PROTOCOL,
          "ok" => result[:failed].empty?,
          "dry_run" => false,
          "dropped" => result[:dropped], "archived" => result[:archived],
          "refreshed" => result[:refreshed], "failed" => result[:failed],
          "health" => health
        }
      end

      def action_keys(rows, action)
        rows.select { |r| r["action"] == action }.map { |r| r["key"] }
      end

      def apply(rows)
        out = { dropped: [], archived: [], refreshed: [], failed: [] }
        delete  = Write::Delete.new(container: @container, call: @call)
        refresh = Write::FetchWorker.new(container: @container, call: @call)

        rows.each do |row|
          key = row["key"]
          begin
            case row["action"]
            when "drop"
              delete.call(key)
              out[:dropped] << key
            when "archive"
              archive_leaf(row)
              delete.call(key)
              out[:archived] << key
            when "refresh"
              refresh.run(key)
              out[:refreshed] << key
            end
          rescue Textus::Error => e
            out[:failed] << { "key" => key, "error" => e.message }
          end
        end
        out
      end

      # Copy the leaf into <store>/archive/<relative-path> before deletion.
      # (Lifted from the retired RetentionSweep#archive_leaf.)
      def archive_leaf(row)
        src  = row["path"]
        root = @container.root.to_s
        rel  = src.delete_prefix("#{root}/")
        dest = File.join(root, "archive", rel)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
      end
    end
  end
end
