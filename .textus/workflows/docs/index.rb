Textus.workflow "store_index" do
  match "artifacts.index"

  step :build do |_, ctx|
    container = ctx.container
    rows = container.manifest.resolver.enumerate.filter_map do |row|
      path = row[:path]
      next unless path && File.exist?(path)

      mentry = row[:manifest_entry]
      etag   = Textus::Etag.for_file(path)
      {
        "key" => row[:key],
        "lane" => mentry.lane,
        "schema" => mentry.schema,
        "owner" => mentry.owner,
        "format" => mentry.format,
        "etag" => etag,
      }
    end
    { "content" => { "entries" => rows, "generated_at" => Time.now.utc.iso8601 } }
  end

  publish
end
