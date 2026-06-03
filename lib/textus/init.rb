require "fileutils"
require "pathname"

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
        # A per-host snapshot, pulled by `textus fetch feeds.machines.local --as=automation`.
        # Nested so it grows to a fleet — add feeds.machines.<host> leaves over SSH
        # (see docs/cookbook/environment-scan.md) without renaming. tracked:false →
        # gitignored (machine info can be sensitive/noisy) but still protocol-readable
        # via `textus get feeds.machines.local`. Delete to opt out. (ADR 0043)
        - key: feeds.machines
          path: feeds/machines
          zone: feeds
          format: yaml
          nested: true
          tracked: false
          kind: intake
          intake:
            handler: machines
            config:
              machines:
                local: { via: local }
      rules:
        - match: feeds.machines.**
          fetch: { ttl: 1h, on_stale: warn } # meaningful on a long-running server
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
              :file_published, :store_loaded, :session_opened,
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
      scaffold_dir = File.expand_path("init/templates", __dir__)
      File.write(File.join(target_root, "hooks", "machine_intake.rb"),
                 File.read(File.join(scaffold_dir, "machine_intake.rb")))
      File.write(File.join(target_root, "manifest.yaml"), DEFAULT_MANIFEST)
      FileUtils.mkdir_p(Textus::Layout.audit_dir(target_root))
      FileUtils.mkdir_p(Textus::Layout.state(target_root))
      FileUtils.mkdir_p(Textus::Layout.locks(target_root))
      File.write(File.join(target_root, ".gitignore"), derived_gitignore(target_root))
      { "protocol" => PROTOCOL, "initialized" => target_root }
    end

    # The store's `.gitignore` is generated, never hand-kept (ADR 0038), and now
    # derived from the manifest: the run subtree plus every `tracked: false`
    # entry's resolved path (ADR 0043).
    def self.derived_gitignore(target_root)
      manifest = Textus::Manifest.load(target_root)
      root = Pathname.new(target_root)
      untracked = manifest.data.entries.reject(&:tracked?).map do |e|
        if e.nested? # a whole subtree of leaf files (feeds.machines.* → zones/feeds/machines/)
          "#{File.join("zones", e.path)}/"
        else
          Pathname.new(Textus::Key::Path.resolve(manifest.data, e)).relative_path_from(root).to_s
        end
      end
      Textus::Layout.gitignore_body(untracked_paths: untracked)
    end
  end
end
