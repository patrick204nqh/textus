# Hooks

Drop one Ruby file per hook. All hooks register through one DSL.
Files anywhere under `.textus/hooks/` (including subdirectories) are loaded at
startup in alphabetical order by full path. Subdirectory names are organizational
only — the registered event and name come from the DSL call, not the file path.

## DSL

```ruby
Textus.hook do |reg|
  reg.on(:resolve_intake, :my_source) do |config:, args:, **|
    { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "…" }
  end

  reg.on(:transform_rows, :my_source) { |rows:, **| rows.map { |r| r.merge(processed: true) } }
  reg.on(:validate,       :my_check)  { |caps:, **| [] }
  reg.on(:entry_put,      :my_listener, keys: ["knowledge.*"]) { |key:, envelope:, **| }

  # Run a side-effect every time textus writes a file to your repo:
  reg.on(:file_published, :notify) do |key:, target:, **|
    warn "wrote #{target} (from #{key})"
  end
end
```

The intake handler above is paired with a manifest entry plus a
top-level `rules:` block for freshness (ttl/on_stale live in
rules, not in the entry):

```yaml
entries:
  - key: feeds.foo
    kind: intake
    path: feeds/foo.md
    zone: feeds
    intake:
      handler: my_source

rules:
  - match: feeds.foo
    fetch:
      ttl: 10m
      on_stale: timed_sync   # warn | sync | timed_sync (default: warn)
```

Events: :resolve_intake, :transform_rows, :validate (rpc — return value used)
        :entry_put, :entry_deleted, :entry_fetched, :entry_renamed,
        :build_completed, :proposal_accepted, :proposal_rejected,
        :file_published, :store_loaded,
        :fetch_started, :fetch_failed, :fetch_backgrounded (pub-sub — return discarded)

See SPEC.md §5.10 for the full table.
