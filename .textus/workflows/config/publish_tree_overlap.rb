# Replaces Doctor::Check::PublishTreeIndexOverlap. Warns when a publish_tree
# target can prune a derived publish_to file unless ignored.

# rubocop:disable Metrics/BlockLength
Textus.workflow "publish-tree-overlap" do
  match "artifacts.doctor.publish-tree-overlap"

  step :check do |_, ctx|
    entries = ctx.container.manifest.data.entries
    trees = entries.select { |entry| entry.nested? && entry.publish_tree }
    derived_targets = entries.flat_map { |entry| Array(entry.publish_to).map { |rel| [entry, rel] } }

    issues = trees.flat_map do |tree|
      target_prefix = "#{tree.publish_tree.chomp("/")}/"

      derived_targets.filter_map do |(derived, rel)|
        next nil unless rel.start_with?(target_prefix)

        rel_to_target = rel.delete_prefix(target_prefix)
        next nil if tree.ignored?(rel_to_target)

        basename = File.basename(rel_to_target)
        {
          "code" => "publish.tree_index_overlap",
          "level" => "warning",
          "subject" => tree.key,
          "message" => "publish_tree '#{tree.publish_tree}' overlaps derived entry " \
                       "'#{derived.key}' publish_to '#{rel}'; the tree's prune will delete it on rebuild",
          "fix" => "add a glob covering '#{rel_to_target}' to entry '#{tree.key}' ignore " \
                   "(e.g. ignore: [\"**/#{basename}\"])",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
