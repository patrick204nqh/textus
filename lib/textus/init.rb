require "fileutils"

module Textus
  module Init
    ZONES = %w[knowledge notebook feeds proposals artifacts].freeze

    DEFAULT_MANIFEST = <<~YAML
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: agent,      can: [propose, keep] }
        - { name: automation, can: [fetch, build] }
      zones:
        - { name: knowledge, kind: canon,     desc: "the maintained source of truth (identity.* lives here)" }
        - { name: notebook,  kind: workspace, owner: agent, desc: "the agent's own durable working notes" }
        - { name: feeds,     kind: quarantine, desc: "external inputs pulled in" }
        - { name: proposals, kind: queue,     desc: "changes awaiting your accept" }
        - { name: artifacts, kind: derived,   desc: "computed, shippable outputs" }
      entries:
        - { key: knowledge.identity, path: knowledge/identity.md, zone: knowledge, schema: null, owner: human:self, kind: leaf }
        - { key: knowledge.notes,    path: knowledge/notes,       zone: knowledge, schema: null, owner: human:self, nested: true, kind: nested }
        - { key: notebook.notes,     path: notebook/notes,        zone: notebook,  schema: null, owner: agent:self, nested: true, kind: nested }
        - { key: proposals.notes,    path: proposals/notes,       zone: proposals, schema: null, owner: agent:self, nested: true, kind: nested }
    YAML

    HOOKS_README = <<~MD
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
          warn "wrote \#{target} (from \#{key})"
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
    MD

    def self.run(target_root)
      raise UsageError.new(".textus/ already exists at #{target_root}") if File.directory?(target_root)

      FileUtils.mkdir_p(File.join(target_root, "schemas"))
      FileUtils.mkdir_p(File.join(target_root, "templates"))
      FileUtils.mkdir_p(File.join(target_root, "hooks"))
      ZONES.each do |z|
        dir = File.join(target_root, "zones", z)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, ".gitkeep"), "")
      end
      File.write(File.join(target_root, "hooks", "README.md"), HOOKS_README)
      File.write(File.join(target_root, "manifest.yaml"), DEFAULT_MANIFEST)
      FileUtils.mkdir_p(Textus::Layout.audit_dir(target_root))
      FileUtils.mkdir_p(Textus::Layout.state(target_root))
      FileUtils.mkdir_p(Textus::Layout.locks(target_root))
      File.write(File.join(target_root, ".gitignore"), Textus::Layout::GITIGNORE)
      { "protocol" => PROTOCOL, "initialized" => target_root }
    end
  end
end
