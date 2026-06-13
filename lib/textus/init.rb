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
        - { name: automation, can: [converge] }
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
            handler: machine-intake
            ttl: 1h # cadence on a long-running server
            config:
              machines:
                local: { via: local }
      rules: []
    YAML

    STEPS_README = <<~MD
      # Steps

      Drop one Ruby file per step. Steps are discovered by convention.
      Files under `.textus/steps/<kind>/<name>.rb` are loaded at
      startup and registered.

      ## Conventions

      The directory name (`<kind>`) must be one of:
      - `fetch`: Acquires data from outside the store.
      - `transform`: Reshapes projection rows.
      - `validate`: Validates data before writing.
      - `observe`: Listens to store events.

      The filename (`<name>.rb`) defines the step name. The class defined
      in the file must be a subclass of `Textus::Step::<Kind>` (e.g.
      `Textus::Step::Fetch`) and be wrapped in the `Textus::Step` module.

      ## Example

      ```ruby
      module Textus
        module Step
          class MyFetch < Fetch
            def call(config:, args:, caps:, **)
              { content: { "foo" => "bar" } }
            end
          end
        end
      end
      ```

      Events: :fetch, :transform, :validate (rpc — return value used)
              :entry_written, :entry_deleted, :entry_fetched, :entry_renamed,
              :entry_produced, :produce_failed,
              :proposal_accepted, :proposal_rejected,
              :entry_published, :store_loaded, :session_opened,
              :entry_fetch_started, :entry_fetch_failed (pub-sub — return discarded)

      See SPEC.md §5.10 for the full table.
    MD

    AGENT_ENTRIES = <<~YAML.gsub(/^/, "  ")
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
          transform: orientation
        kind: produced
    YAML

    def self.run(target_root, with_agent: false) # rubocop:disable Metrics/AbcSize
      raise UsageError.new(".textus/ already exists at #{target_root}") if File.directory?(target_root)

      FileUtils.mkdir_p(File.join(target_root, "schemas"))
      FileUtils.mkdir_p(File.join(target_root, "templates"))
      FileUtils.mkdir_p(File.join(target_root, "steps/fetch"))
      FileUtils.mkdir_p(File.join(target_root, "steps/transform"))
      FileUtils.mkdir_p(File.join(target_root, "steps/validate"))
      FileUtils.mkdir_p(File.join(target_root, "steps/observe"))
      ZONES.each do |z|
        dir = File.join(target_root, "data", z)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, ".gitkeep"), "")
      end
      File.write(File.join(target_root, "steps/README.md"), STEPS_README)
      scaffold_dir = File.expand_path("init/templates", __dir__)
      File.write(File.join(target_root, "steps/fetch/machine-intake.rb"),
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
        "orientation_reducer.rb" => File.join("steps/transform", "orientation.rb"),
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
        if e.nested? # a whole subtree of leaf files (artifacts.feeds.machines.* → data/artifacts/feeds/machines/)
          "#{File.join("data", e.path)}/"
        else
          Pathname.new(Textus::Key::Path.resolve(manifest.data, e)).relative_path_from(root).to_s
        end
      end
      Textus::Layout.gitignore_body(untracked_paths: untracked)
    end
  end
end
