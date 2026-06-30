# frozen_string_literal: true

Textus.workflow "spec" do
  match "artifacts.spec"

  step :collect do |_data, ctx|
    root = ctx.container.root
    glob = File.join(root, "data", "knowledge", "specs", "*.md")

    sections = Dir.glob(glob).filter_map do |path|
      body = File.read(path)
      next if body.strip.empty?

      title_line = body[/^\#{1,6}\s+.+$/]
      next unless title_line

      title = title_line.sub(/^#+\s+/, "").strip
      anchor = title.downcase.strip.gsub(/[^\w-]+/, "-").gsub(/-+$/, "")

      body_no_title = body.sub(/^\#{1,6}\s+.+$\n?/, "").strip

      { "anchor" => anchor, "title" => title, "body" => body_no_title }
    end

    { "content" => { "sections" => sections } }
  end

  publish
end
