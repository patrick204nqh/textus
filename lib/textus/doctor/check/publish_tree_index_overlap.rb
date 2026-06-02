module Textus
  module Doctor
    class Check
      # ADR 0047 Decision 4. A publish_tree entry prunes its WHOLE target dir on
      # every build. If a derived entry's publish_to writes a file into that same
      # dir, the tree's prune will delete it unless the tree `ignore`s that
      # filename. Warn so the author adds the ignore before prune eats the index.
      class PublishTreeIndexOverlap < Check
        def call
          entries = manifest.data.entries
          trees = entries.select { |e| e.nested? && e.publish_tree }
          return [] if trees.empty?

          derived_targets = entries.flat_map do |e|
            Array(e.publish_to).map { |rel| [e, rel] }
          end

          trees.flat_map do |tree|
            target_prefix = "#{tree.publish_tree.chomp("/")}/"
            derived_targets.filter_map do |(derived, rel)|
              next nil unless rel.start_with?(target_prefix)

              basename = File.basename(rel)
              next nil if tree.ignored?(basename)

              issue(tree, derived, rel, basename)
            end
          end
        end

        private

        def issue(tree, derived, rel, basename)
          {
            "code" => "publish.tree_index_overlap",
            "level" => "warning",
            "subject" => tree.key,
            "message" => "publish_tree '#{tree.publish_tree}' overlaps derived entry " \
                         "'#{derived.key}' publish_to '#{rel}'; the tree's prune will delete it on rebuild",
            "fix" => "add '#{basename}' to entry '#{tree.key}' ignore: [\"#{basename}\"]",
          }
        end
      end
    end
  end
end
