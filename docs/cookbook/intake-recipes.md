# Intake recipes

> **Cookbook** · for integrators · **read when** wiring an external source into a `feeds` zone

Each recipe is the same shape: **declare an entry + rule → write a hook that does
the I/O → delegate parsing to a built-in.** You own the network call; textus owns
the parse. This keeps SPEC §5.4 intact — core makes no implicit network calls.

Built-in parsers available to delegate to: `json`, `csv`, `markdown-links`,
`ical-events`, `rss` (see [`../reference/zones.md`](../reference/zones.md)). Each
expects raw bytes in `config["bytes"]`.

## HTTP JSON API

```ruby
# .textus/hooks/http_json.rb
Textus.hook do |reg|
  reg.on(:resolve_intake, :http_json) do |config:, **|
    require "net/http"
    body = Net::HTTP.get(URI(config.fetch("url")))         # YOU own the I/O
    reg.invoke(:resolve_intake, :json, config: { "bytes" => body })  # built-in parser
  end
end
```

```yaml
# manifest.yaml
entries:
  - key: feeds.api.users
    zone: feeds
    intake: { handler: http_json, config: { url: "https://api.example.com/users" } }
rules:
  - { match: feeds.api.**, fetch: { ttl: 15m, on_stale: timed_sync } }
```

Run: `textus fetch feeds.api.users --as=automation`

## RSS feed

```ruby
# .textus/hooks/http_rss.rb
Textus.hook do |reg|
  reg.on(:resolve_intake, :http_rss) do |config:, **|
    require "net/http"
    body = Net::HTTP.get(URI(config.fetch("url")))
    reg.invoke(:resolve_intake, :rss, config: { "bytes" => body })
  end
end
```

## iCal URL

```ruby
# .textus/hooks/http_ical.rb
Textus.hook do |reg|
  reg.on(:resolve_intake, :http_ical) do |config:, **|
    require "net/http"
    body = Net::HTTP.get(URI(config.fetch("url")))
    reg.invoke(:resolve_intake, :"ical-events", config: { "bytes" => body })
  end
end
```

## Local file

```ruby
# .textus/hooks/local_csv.rb
Textus.hook do |reg|
  reg.on(:resolve_intake, :local_csv) do |config:, **|
    body = File.read(config.fetch("path"))                 # local read, no network
    reg.invoke(:resolve_intake, :csv, config: { "bytes" => body })
  end
end
```

## Notion page (custom shape — no built-in parser)

When no built-in parser fits, return the envelope shape directly
(`{ _meta:, body: }`):

```ruby
# .textus/hooks/notion.rb
Textus.hook do |reg|
  reg.on(:resolve_intake, :notion) do |config:, **|
    page_id = config.fetch("page_id")
    body = NotionClient.new.fetch_markdown(page_id)        # YOU own the SDK + auth
    { _meta: { "fetched_at" => Time.now.utc.iso8601 }, body: body }
  end
end
```

> **Secrets:** credentials belong in *your* hook's environment (e.g. `ENV`),
> never in `manifest.yaml` `config:` — the manifest is committed.
