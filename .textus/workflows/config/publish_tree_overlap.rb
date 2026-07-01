# Replaces Doctor::Check::PublishTreeIndexOverlap. Checks no publish_tree shares
# a target directory with a derived entry without an ignore: pattern.

Textus.workflow "publish-tree-overlap" do
  match "artifacts.doctor.publish-tree-overlap"

  step :check do |_, ctx|
    manifest = ctx.container.manifest
    entries = manifest.data.entries
    tree_entries = entries.select { |e| e.publish_tree }
    derived_entries = entries.select { |e| e.publish_to.any? }
    issues = []
    tree_entries.each do |tree_e|
      tree_path = tree_e.publish_tree.chomp("/")
      derived_entries.each do |derived_e|
        derived_to = derived_e.publish_to.map { |t| t.respond_to?(:to) ? t.to : t.to_s }.compact
        derived_to.each do |to|
          next unless to.start_with?(tree_path)
          next if tree_e.ignored?(to)
          issues << { "code" => "publish.tree_overlap", "severity" => "warning",
                      "subject" => tree_e.key,
                      "message" => "publish_tree '#{tree_path}' overlaps with '#{derived_e.key}' target '#{to}'",
                      "fix" => "add an ignore: pattern to '#{tree_e.key}' that excludes '#{to}'" }
        end
      end
    end
    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
