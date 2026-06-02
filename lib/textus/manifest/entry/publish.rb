module Textus
  class Manifest
    class Entry
      # ADR 0049: the publish design is a three-key concept (ADR 0047 table)
      # realized as one resolved sum type. Each directory entry resolves, once,
      # to one Publish::* mode that owns its publish algorithm — no nil-cascade,
      # no pairwise exclusivity guards, one shared subtree mirror.
      #
      #   None      — nothing to publish
      #   ToPaths   — publish_to: 1 stored file -> N fixed repo paths
      #   EachFile  — publish_each (file leaves): 1 leaf file -> 1 templated path
      #   EachDir   — publish_each + index_filename: 1 leaf subtree -> 1 templated dir
      #   Tree      — publish_tree: whole entry subtree -> 1 dir, no keys
      module Publish
        # Resolve an entry to its single publish mode. Raises one UsageError if
        # more than one of {publish_to, publish_each, publish_tree} is set —
        # exclusivity is structural here, not four scattered pairwise guards.
        def self.resolve(entry)
          set = []
          set << "publish_to"   unless Array(entry.publish_to).empty?
          set << "publish_each" unless entry.publish_each.nil?
          set << "publish_tree" unless entry.publish_tree.nil?

          if set.length > 1
            raise Textus::UsageError.new(
              "entry '#{entry.key}': #{set.join(", ")} are mutually exclusive — an entry publishes exactly one way",
            )
          end

          mode_for(entry, set.first)
        end

        def self.mode_for(entry, key)
          case key
          when "publish_to"   then ToPaths.new(entry)
          when "publish_tree" then Tree.new(entry)
          when "publish_each" then entry.index_filename ? EachDir.new(entry) : EachFile.new(entry)
          else None.new(entry)
          end
        end
        private_class_method :mode_for
      end
    end
  end
end
