Textus.fetch(:local_file) do |config:, **|
  path = config["path"] or raise "local_file fetch requires source.config.path"
  abs = File.absolute_path?(path) ? path : File.expand_path(path)
  raise "local_file: not found: #{abs}" unless File.exist?(abs)

  {
    _meta: { "last_refreshed_at" => Time.now.utc.iso8601, "source_path" => path },
    body: File.read(abs),
  }
end
