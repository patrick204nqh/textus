Textus.action(:"local-file") do |config:, store:, args:|
  path = config["path"] or raise "local-file action requires source.config.path"
  abs = File.absolute_path?(path) ? path : File.expand_path(path)
  raise "local-file: not found: #{abs}" unless File.exist?(abs)

  {
    frontmatter: { "last_refreshed_at" => Time.now.utc.iso8601, "source_path" => path },
    body: File.read(abs),
  }
end
