module Textus
  class Manifest
    class Entry
      # ADR 0049: the publish design is a key-split concept (ADR 0047 table)
      # realized as one resolved sum type. Each directory entry resolves, once,
      # to one Publish::* mode that owns its publish algorithm — no nil-cascade,
      # no pairwise exclusivity guards, one shared subtree mirror. ADR 0051
      # removed `publish_each` (both leaf modes); ADR 0052 folded the two surviving
      # keys into one `publish:` block (`to:` xor `tree:`). The surface is two modes:
      #
      #   None      — nothing to publish (no publish: block)
      #   ToPaths   — publish: { to: [...] }  — 1 stored file -> N fixed repo paths
      #   Tree      — publish: { tree: "dir" } — whole entry subtree -> 1 dir, no keys
      module Publish
        # Resolve an entry to its single publish mode. The publish config is the
        # ADR 0052 `publish:` block, sourced into entry.publish_to/publish_tree.
        # Raises one UsageError if both `publish.to` and `publish.tree` are set —
        # the block groups the two but does not make exclusivity structural, so
        # this stays the one enforcement point (ADR 0052 D2).
        def self.resolve(entry)
          reject_removed_publish_each(entry)

          set = []
          set << "publish.to"   unless Array(entry.publish_to).empty?
          set << "publish.tree" unless entry.publish_tree.nil?

          if set.length > 1
            raise Textus::UsageError.new(
              "entry '#{entry.key}': #{set.join(" and ")} are mutually exclusive — an entry publishes exactly one way",
            )
          end

          mode_for(entry, set.first)
        end

        def self.reject_removed_publish_each(entry)
          return unless entry.raw["publish_each"]

          raise Textus::UsageError.new(
            "entry '#{entry.key}': publish_each was removed in 0.42.0 (ADR 0051) — " \
            "mirror the subtree with `publish: { tree: \"...\" }`.",
          )
        end
        private_class_method :reject_removed_publish_each

        def self.mode_for(entry, key)
          case key
          when "publish.to"   then ToPaths.new(entry)
          when "publish.tree" then Tree.new(entry)
          else None.new(entry)
          end
        end
        private_class_method :mode_for
      end
    end
  end
end
