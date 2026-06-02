module Textus
  class Manifest
    class Entry
      module Publish
        # publish_tree (ADR 0047): mirror this entry's whole subtree to one
        # target dir by real path. No resolver, no keys — files are opaque
        # payload (envelope nil). The prune honors `ignore` so a derived index
        # (e.g. a SKILL.md written by a separate entry into the same dir)
        # survives the whole-target prune (ADR 0047 D4).
        class Tree < Mode
          def publish(pctx, prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
            target_rel = entry.publish_tree
            target_dir = repo_abs(pctx, target_rel)
            unless inside_repo?(pctx, target_dir)
              raise Textus::PublishError.new(
                "entry '#{entry.key}': publish_tree target '#{target_rel}' escapes repo root",
              )
            end

            result = SubtreeMirror.new(entry, pctx).mirror(
              base: store_base(pctx),
              walk_root: store_base(pctx),
              target_dir: target_dir,
              key: entry.key,
              envelope: nil,
              prune_honors_ignore: true,
            )
            { kind: :leaves, value: result[:written], pruned: result[:pruned] }
          end

          def validate!
            publish_tree = entry.publish_tree
            raise UsageError.new("entry '#{entry.key}': publish_tree must be a string") unless publish_tree.is_a?(String)

            unless entry.index_filename.nil?
              raise UsageError.new(
                "entry '#{entry.key}': index_filename and publish_tree are mutually exclusive — " \
                "publish_tree mirrors a whole subtree by path and never enumerates an index.",
              )
            end

            used_vars = publish_tree.scan(Template::VAR_RE).flatten
            return if used_vars.empty?

            raise UsageError.new(
              "entry '#{entry.key}': publish_tree names a single directory and takes no template variable(s) " \
              "#{used_vars.map { |v| "{#{v}}" }.join(", ")} — it mirrors the whole subtree to one target dir.",
            )
          end
        end
      end
    end
  end
end
