require "fileutils"

module Textus
  module Protocol
    module Retention
      class Base
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

        def archive_leaf(row)
          src  = row["path"]
          dest = @container.layout.archive_path(src)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
        end

        # Intentionally bypasses use-case layer — retention is a system cleanup
        # operation (automation role). Using the delete use case would fire
        # cascade events that could re-trigger retention in an infinite loop.
        def delete(key)
          mentry = @container.manifest.resolver.resolve(key).entry
          @container.writer.delete(key, mentry: mentry, call: @call)
        end
      end
    end
  end
end
