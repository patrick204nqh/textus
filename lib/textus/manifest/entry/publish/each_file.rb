module Textus
  class Manifest
    class Entry
      module Publish
        # publish_each over file leaves (no index_filename): one stored leaf file
        # copied to one templated repo path. No prune — each leaf is a single
        # file, not a subtree.
        class EachFile < Each
          def publish_leaf(row, target_abs, pctx)
            Textus::Ports::Publisher.publish(source: row[:path], target: target_abs, store_root: pctx.root)
            pctx.emit(:file_published, key: row[:key], envelope: pctx.reader.call(row[:key]),
                                       source: row[:path], target: target_abs)
            { written: [{ "source" => row[:path], "target" => target_abs }], pruned: [] }
          end

          def validate!
            used_vars = validate_template_basics
            return if used_vars.intersect?(Template::REQUIRED_DISCRIMINATOR_VARS)

            raise UsageError.new(
              "entry '#{entry.key}': publish_each must reference at least one of {leaf}, {basename}, or {key} " \
              "(else every leaf would clobber the same target).",
            )
          end
        end
      end
    end
  end
end
