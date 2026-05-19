Textus.fetcher(:"local-file") do |config:, store:|
  path = config["path"] or raise "local-file fetcher requires source.config.path"
  abs = File.absolute_path?(path) ? path : File.expand_path(path)
  raise "local-file: not found: #{abs}" unless File.exist?(abs)

  {
    frontmatter: { "last_refreshed_at" => Time.now.utc.iso8601, "source_path" => path },
    body: File.read(abs),
  }
end
