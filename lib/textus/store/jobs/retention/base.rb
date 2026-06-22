require "fileutils"

module Textus
  class Store
    module Jobs
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
            root = @container.root.to_s
            rel  = src.delete_prefix("#{root}/")
            dest = File.join(root, "archive", rel)
            FileUtils.mkdir_p(File.dirname(dest))
            FileUtils.cp(src, dest)
          end

          def delete(key)
            mentry = @container.manifest.resolver.resolve(key).entry
            @container.pipeline.delete(key, mentry: mentry, call: @call)
          end
        end
      end
    end
  end
end
