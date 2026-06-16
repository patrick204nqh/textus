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
      lanes:
        - { name: knowledge, kind: canon,     desc: "the maintained source of truth (identity.* lives here)" }
        - { name: notebook,  kind: workspace, owner: agent, desc: "the agent's own durable working notes" }
        - { name: proposals, kind: queue,     desc: "changes awaiting your accept" }
        - { name: artifacts, kind: machine,   desc: "machine-maintained: external inputs (artifacts.feeds.*) + computed outputs (artifacts.derived.*)" }
      entries:
        - { key: knowledge.identity, path: data/knowledge/identity.md, lane: knowledge, schema: null, owner: human:self, kind: leaf }
        - { key: knowledge.notes,    path: data/knowledge/notes,       lane: knowledge, schema: null, owner: human:self, nested: true, kind: nested }
        - { key: notebook.notes,     path: data/notebook/notes,        lane: notebook,  schema: null, owner: agent:self, nested: true, kind: nested }
        - { key: proposals.notes,    path: data/proposals/notes,       lane: proposals, schema: null, owner: agent:self, nested: true, kind: nested }
        # A per-host snapshot, populated by a registered workflow. Nested so it
        # grows to a fleet — add leaves over SSH without renaming. tracked:false →
        # gitignored (machine info can be sensitive/noisy) but still protocol-readable
        # via `textus get artifacts.feeds.machines.local`. Delete to opt out. (ADR 0043)
        - key: artifacts.feeds.machines
          path: data/artifacts/feeds/machines
          lane: artifacts
          format: yaml
          nested: true
          tracked: false
          kind: nested
      rules: []
    YAML

    AGENT_ENTRIES = <<~YAML.gsub(/^/, "  ")
      - { key: knowledge.project, path: data/knowledge/project.md, lane: knowledge, schema: project, owner: human:self, kind: leaf }
      - { key: knowledge.runbooks, path: data/knowledge/runbooks, lane: knowledge, schema: runbook, owner: human:self, nested: true, kind: nested }
      - key: artifacts.derived.orientation
        path: data/artifacts/derived/orientation.json
        lane: artifacts
        publish:
        - { to: CLAUDE.md, template: orientation.mustache, inject_boot: true }
        - { to: AGENTS.md, template: orientation.mustache, inject_boot: true }
        kind: produced
    YAML

    def self.run(target_root, with_agent: false)
      check_target!(target_root)
      scaffold_dir = File.expand_path("init/templates", __dir__)
      create_directories(target_root)
      write_manifest(target_root, with_agent:)
      mcp_status = scaffold_agent(target_root, scaffold_dir, with_agent:)
      setup_state_dirs(target_root)
      write_gitignore(target_root)
      build_result(target_root, with_agent:, mcp_status:)
    end

    def self.check_target!(target_root)
      raise UsageError.new(".textus/ already exists at #{target_root}") if File.directory?(target_root)
    end

    def self.create_directories(target_root)
      FileUtils.mkdir_p(File.join(target_root, "schemas"))
      FileUtils.mkdir_p(File.join(target_root, "templates"))
      FileUtils.mkdir_p(File.join(target_root, "workflows"))
      ZONES.each do |z|
        dir = File.join(target_root, "data", z)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, ".gitkeep"), "")
      end
    end

    def self.write_manifest(target_root, with_agent:)
      File.write(File.join(target_root, "manifest.yaml"), manifest_yaml(with_agent: with_agent))
    end

    def self.scaffold_agent(target_root, scaffold_dir, with_agent:)
      return nil unless with_agent

      scaffold_agent_profile(target_root, scaffold_dir)
      write_mcp_config(target_root, scaffold_dir)
    end

    def self.setup_state_dirs(target_root)
      FileUtils.mkdir_p(Textus::Layout.audit_dir(target_root))
      FileUtils.mkdir_p(Textus::Layout.state(target_root))
      FileUtils.mkdir_p(Textus::Layout.locks(target_root))
    end

    def self.write_gitignore(target_root)
      File.write(File.join(target_root, ".gitignore"), derived_gitignore(target_root))
    end

    def self.build_result(target_root, with_agent:, mcp_status:)
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
          rel = e.path.start_with?("data/") ? e.path : File.join("data", e.path)
          "#{rel}/"
        else
          Pathname.new(Textus::Key::Path.resolve(manifest.data, e)).relative_path_from(root).to_s
        end
      end
      Textus::Layout.gitignore_body(untracked_paths: untracked)
    end
  end
end
