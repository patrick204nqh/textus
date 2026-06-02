module Textus
  class Manifest
    class Entry
      # ADR 0049: the publish design is a key-split concept (ADR 0047 table)
      # realized as one resolved sum type. Each directory entry resolves, once,
      # to one Publish::* mode that owns its publish algorithm — no nil-cascade,
      # no pairwise exclusivity guards, one shared subtree mirror. ADR 0051
      # removed `publish_each` (both leaf modes); the surface is now two modes:
      #
      #   None      — nothing to publish
      #   ToPaths   — publish_to: 1 stored file -> N fixed repo paths
      #   Tree      — publish_tree: whole entry subtree -> 1 dir, no keys
      module Publish
        # Resolve an entry to its single publish mode. Raises one UsageError if
        # both publish_to and publish_tree are set — exclusivity is structural
        # here, not scattered pairwise guards. A removed `publish_each:` key is
        # rejected loudly with its replacement (ADR 0051).
        def self.resolve(entry)
          reject_removed_publish_each(entry)

          set = []
          set << "publish_to"   unless Array(entry.publish_to).empty?
          set << "publish_tree" unless entry.publish_tree.nil?

          if set.length > 1
            raise Textus::UsageError.new(
              "entry '#{entry.key}': #{set.join(", ")} are mutually exclusive — an entry publishes exactly one way",
            )
          end

          mode_for(entry, set.first)
        end

        def self.reject_removed_publish_each(entry)
          return unless entry.raw["publish_each"]

          raise Textus::UsageError.new(
            "entry '#{entry.key}': publish_each was removed in 0.42.0 (ADR 0051) — " \
            "mirror the subtree with publish_tree (and index_filename to keep the index addressable).",
          )
        end
        private_class_method :reject_removed_publish_each

        def self.mode_for(entry, key)
          case key
          when "publish_to"   then ToPaths.new(entry)
          when "publish_tree" then Tree.new(entry)
          else None.new(entry)
          end
        end
        private_class_method :mode_for
      end
    end
  end
end
