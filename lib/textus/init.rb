require "fileutils"
require "pathname"

module Textus
  module Init
    ZONES = %w[knowledge notebook proposals artifacts].freeze

    DEFAULT_MANIFEST = <<~YAML
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: agent,      can: [propose, keep] }
        - { name: automation, can: [reconcile] }
      zones:
        - { name: knowledge, kind: canon,     desc: "the maintained source of truth (identity.* lives here)" }
        - { name: notebook,  kind: workspace, owner: agent, desc: "the agent's own durable working notes" }
        - { name: proposals, kind: queue,     desc: "changes awaiting your accept" }
        - { name: artifacts, kind: machine,   desc: "machine-maintained: external inputs (artifacts.feeds.*) + computed outputs (artifacts.derived.*)" }
      entries:
        - { key: knowledge.identity, path: knowledge/identity.md, zone: knowledge, schema: null, owner: human:self, kind: leaf }
        - { key: knowledge.notes,    path: knowledge/notes,       zone: knowledge, schema: null, owner: human:self, nested: true, kind: nested }
        - { key: notebook.notes,     path: notebook/notes,        zone: notebook,  schema: null, owner: agent:self, nested: true, kind: nested }
        - { key: proposals.notes,    path: proposals/notes,       zone: proposals, schema: null, owner: agent:self, nested: true, kind: nested }
        # A per-host snapshot, refreshed from its declared intake by `textus drain` (scheduled, or on demand).
        # Nested so it grows to a fleet — add artifacts.feeds.machines.<host> leaves over SSH
        # (see docs/cookbook/environment-scan.md) without renaming. tracked:false →
        # gitignored (machine info can be sensitive/noisy) but still protocol-readable
        # via `textus get artifacts.feeds.machines.local`. Delete to opt out. (ADR 0043)
        - key: artifacts.feeds.machines
          path: artifacts/feeds/machines
          zone: artifacts
          format: yaml
          nested: true
          tracked: false
          kind: produced
          source:
            from: handler
            handler: machines
            ttl: 1h # cadence on a long-running server
            config:
              machines:
                local: { via: local }
      rules: []
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
        reg.on(:resolve_handler, :my_source) do |config:, args:, **|
          { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "…" }
        end

        reg.on(:transform_rows, :my_source) { |rows:, **| rows.map { |r| r.merge(processed: true) } }
        reg.on(:validate,       :my_check)  { |caps:, **| [] }
        reg.on(:entry_written,      :my_listener, keys: ["knowledge.*"]) { |key:, envelope:, **| }

        # Run a side-effect every time textus writes a file to your repo:
        reg.on(:entry_published, :notify) do |key:, target:, **|
          warn "wrote \#{target} (from \#{key})"
        end
      end
      ```

      The intake handler above is paired with a manifest entry whose
      `source:` block declares the handler and its refresh cadence
      (`ttl`). Age GC (drop/archive) lives in a top-level `retention:`
      rule, not on the entry:

      ```yaml
      entries:
        - key: artifacts.feeds.foo
          kind: produced
          path: artifacts/feeds/foo.md
          zone: artifacts
          source:
            from: handler
            handler: my_source
            ttl: 10m        # refresh cadence for this intake

      rules:
        - match: artifacts.feeds.foo
          retention:
            ttl: 30d
            action: archive   # drop | archive (age GC of stored rows)
      ```

      Events: :resolve_handler, :transform_rows, :validate (rpc — return value used)
              :entry_written, :entry_deleted, :entry_fetched, :entry_renamed,
              :entry_produced, :produce_failed, :reconcile_failed,
              :proposal_accepted, :proposal_rejected,
              :entry_published, :store_loaded, :session_opened,
              :entry_fetch_started, :entry_fetch_failed (pub-sub — return discarded)

      See SPEC.md §5.10 for the full table.
    MD

    AGENT_ENTRIES = <<~YAML.gsub(/^/, "  ")
      # --with-agent profile: project facts + runbooks feed the orientation
      # projection below, which `textus drain` renders to CLAUDE.md/AGENTS.md.
      - { key: knowledge.project, path: knowledge/project.md, zone: knowledge, schema: project, owner: human:self, kind: leaf }
      - { key: knowledge.runbooks, path: knowledge/runbooks, zone: knowledge, schema: runbook, owner: human:self, nested: true, kind: nested }
      - key: artifacts.derived.orientation
        path: artifacts/derived/orientation.json
        zone: artifacts
        publish:
        - { to: CLAUDE.md, template: orientation.mustache, inject_boot: true }
        - { to: AGENTS.md, template: orientation.mustache, inject_boot: true }
        source:
          from: project
          select:
          - knowledge.project
          - knowledge.runbooks
          transform: orientation_reducer
        kind: produced
    YAML

    def self.run(target_root, with_agent: false)
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
      File.write(File.join(target_root, "manifest.yaml"), manifest_yaml(with_agent: with_agent))
      mcp_status = nil
      if with_agent
        scaffold_agent_profile(target_root, scaffold_dir)
        mcp_status = write_mcp_config(target_root, scaffold_dir)
      end
      FileUtils.mkdir_p(Textus::Layout.audit_dir(target_root))
      FileUtils.mkdir_p(Textus::Layout.state(target_root))
      FileUtils.mkdir_p(Textus::Layout.locks(target_root))
      File.write(File.join(target_root, ".gitignore"), derived_gitignore(target_root))
      result = { "protocol" => PROTOCOL, "initialized" => target_root, "profile" => with_agent ? "agent" : "default" }
      result["mcp_config"] = mcp_status if with_agent
      result
    end

    # Composes the agent profile by inserting AGENT_ENTRIES immediately before the
    # top-level `rules:` block of DEFAULT_MANIFEST — that block is load-bearing for
    # this `.sub`; removing it from DEFAULT_MANIFEST would silently drop the entries.
    def self.manifest_yaml(with_agent:)
      return DEFAULT_MANIFEST unless with_agent

      DEFAULT_MANIFEST.sub(/^rules:/, "#{AGENT_ENTRIES}rules:")
    end

    # Copies the proven orientation bundle into a freshly-init'd store.
    def self.scaffold_agent_profile(target_root, scaffold_dir)
      {
        "project.schema.yaml" => File.join("schemas", "project.yaml"),
        "runbook.schema.yaml" => File.join("schemas", "runbook.yaml"),
        "orientation.mustache" => File.join("templates", "orientation.mustache"),
        "orientation_reducer.rb" => File.join("hooks", "orientation_reducer.rb"),
      }.each do |src, dest|
        File.write(File.join(target_root, dest), File.read(File.join(scaffold_dir, src)))
      end
    end

    # The one file init writes outside .textus/: a starter .mcp.json at the
    # project root. Write-once — never clobber a hand-authored config. The
    # command form assumes a gem-installed `textus` on PATH; the user owns
    # the file after this first write.
    def self.write_mcp_config(target_root, scaffold_dir)
      dest = File.join(File.dirname(target_root), ".mcp.json")
      return "skipped" if File.exist?(dest)

      File.write(dest, File.read(File.join(scaffold_dir, "mcp.json")))
      "written"
    end

    # The store's `.gitignore` is generated, never hand-kept (ADR 0038), and now
    # derived from the manifest: the run subtree plus every `tracked: false`
    # entry's resolved path (ADR 0043).
    def self.derived_gitignore(target_root)
      manifest = Textus::Manifest.load(target_root)
      root = Pathname.new(target_root)
      untracked = manifest.data.entries.reject(&:tracked?).map do |e|
        if e.nested? # a whole subtree of leaf files (artifacts.feeds.machines.* → zones/artifacts/feeds/machines/)
          "#{File.join("zones", e.path)}/"
        else
          Pathname.new(Textus::Key::Path.resolve(manifest.data, e)).relative_path_from(root).to_s
        end
      end
      Textus::Layout.gitignore_body(untracked_paths: untracked)
    end
  end
end
