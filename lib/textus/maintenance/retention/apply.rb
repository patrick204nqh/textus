require "fileutils"

module Textus
  module Maintenance
    module Retention
      # The destructive half of convergence: apply retention rows (drop/archive).
      # Lifted verbatim from the legacy reconcile apply/archive_leaf so drain/serve and
      # the `sweep` job handler share one path. Runs as the caller's role — never
      # self-elevates (ADR 0079/0093: destructiveness decides authority).
      class Apply
        def initialize(container:, call:)
          @container = container
          @call = call
        end

        def call(rows)
          out = { dropped: [], archived: [], failed: [] }
          rows.each do |row|
            key = row["key"]
            begin
              case row["action"]
              when "drop"
                delete(key)
                out[:dropped] << key
              when "archive"
                archive_leaf(row)
                delete(key)
                out[:archived] << key
              end
            rescue Textus::Error => e
              out[:failed] << { "key" => key, "error" => e.message }
            end
          end
          out
        end

        private

        # Copy the leaf into <store>/archive/<relative-path> before deletion.
        def archive_leaf(row)
          src  = row["path"]
          root = @container.root.to_s
          rel  = src.delete_prefix("#{root}/")
          dest = File.join(root, "archive", rel)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
        end

        def delete(key)
          Textus::Dispatch::Actions::KeyDelete.new(key: key).call(container: @container, call: @call)
        end
      end
    end
  end
end
