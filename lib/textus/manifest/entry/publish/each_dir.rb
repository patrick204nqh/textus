module Textus
  class Manifest
    class Entry
      module Publish
        # publish_each + index_filename (ADR 0046): each leaf is a whole subtree
        # copied into one templated directory, layout preserved, then pruned.
        # The template names the target DIRECTORY (not the index file).
        class EachDir < Each
          def publish_leaf(row, target_abs, pctx)
            SubtreeMirror.new(entry, pctx).mirror(
              base: store_base(pctx),
              walk_root: File.dirname(row[:path]),
              target_dir: target_abs,
              key: row[:key],
              envelope: pctx.reader.call(row[:key]),
              prune_honors_ignore: false,
            )
          end

          def validate!
            used_vars = validate_template_basics
            reject_file_only_vars(used_vars)
            reject_index_filename_segment
            reject_file_looking_segment
            return if used_vars.intersect?(%w[leaf key])

            raise UsageError.new(
              "entry '#{entry.key}': directory-leaf publish_each must reference {leaf} or {key} " \
              "(else every leaf would clobber the same directory).",
            )
          end

          private

          def reject_file_only_vars(used_vars)
            forbidden = used_vars & %w[basename ext]
            return if forbidden.empty?

            raise UsageError.new(
              "entry '#{entry.key}': publish_each names a directory " \
              "(index_filename: '#{entry.index_filename}'); {basename}/{ext} are file-only — " \
              "use {leaf} or {key}.",
            )
          end

          def reject_index_filename_segment
            return unless last_segment == entry.index_filename

            raise UsageError.new(
              "entry '#{entry.key}': directory-leaf publish_each must name the target DIRECTORY, " \
              "not the index file — drop the trailing '/#{entry.index_filename}' " \
              "(the whole leaf subtree is copied into the named directory).",
            )
          end

          def reject_file_looking_segment
            ext = File.extname(last_segment)
            return if ext.empty?

            raise UsageError.new(
              "entry '#{entry.key}': directory-leaf publish_each names a DIRECTORY target, but its " \
              "final segment '#{last_segment}' looks like a file (extension '#{ext}') — " \
              "drop the extension (the whole leaf subtree is copied into the named directory).",
            )
          end

          def last_segment
            entry.publish_each.sub(%r{/\z}, "").split("/").last
          end
        end
      end
    end
  end
end
