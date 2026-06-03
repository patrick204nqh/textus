require "fileutils"

module Textus
  module Write
    # Applies retention actions reported by Read::Retainable. `expire` deletes
    # the leaf through the role gate; `archive` copies it to
    # <root>/archive/<relative-path> first, then deletes. Rows whose zone the
    # caller's role cannot write surface in `failed` rather than aborting.
    class RetentionSweep
      extend Textus::Contract::DSL

      verb     :retain
      summary  "Apply each entry's retention policy; prune expired versions."
      surfaces :cli
      cli      "retain"
      arg :prefix, String, description: "restrict to keys starting with this dotted prefix"
      arg :zone,   String, description: "restrict to entries in this zone"

      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call(prefix: nil, zone: nil)
        rows = Textus::Read::Retainable.new(container: @container, call: @call)
                                       .call(prefix: prefix, zone: zone)
        delete_op = Textus::Write::Delete.new(container: @container, call: @call)
        expired   = []
        archived  = []
        failed    = []

        rows.each do |row|
          key = row["key"]
          begin
            archive_leaf(row) if row["action"] == "archive"
            delete_op.call(key)
            (row["action"] == "archive" ? archived : expired) << key
          rescue Textus::Error => e
            failed << { "key" => key, "error" => e.message }
          end
        end

        {
          "protocol" => Textus::PROTOCOL,
          "ok" => failed.empty?,
          "expired" => expired,
          "archived" => archived,
          "failed" => failed,
        }
      end

      private

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
