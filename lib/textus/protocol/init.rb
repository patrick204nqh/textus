require "fileutils"
require "pathname"
require "yaml"

module Textus
  module Protocol
    module Init
      ZONES = %w[knowledge scratchpad proposals artifacts raw].freeze

      DEFAULT_MANIFEST = <<~YAML
        version: textus/4
        data:
          knowledge:
            - key: knowledge.loop.execution
              naming: sequential
              schema: runbook
            - key: knowledge.loop.intent
              naming: sequential
            - key: knowledge.loop.constraint
            - key: knowledge.loop.judgment
            - key: knowledge.loop.evidence
              naming: sequential
            - key: knowledge.loop.feedback
          scratchpad:
            - key: scratchpad.notes
              tracked: false
            - key: scratchpad.sessions
              tracked: false
            - key: scratchpad.scripts
              tracked: false
          proposals:
            - key: proposals.notes
          raw:
            - key: raw
              format: yaml
          artifacts:
            - key: artifacts.boot
              format: json
      YAML

      AGENT_ENTRIES = <<~YAML
        data:
          artifacts:
            - key: artifacts.derived.orientation
              format: json
      YAML

      def self.run(target_root, with_agent: false)
        check_target!(target_root)
        scaffold_dir = File.expand_path("init/templates", __dir__)
        create_directories(target_root)
        write_manifest(target_root, with_agent:)
        mcp_status = scaffold_agent(target_root, scaffold_dir, with_agent:)
        write_gitignore(target_root)
        build_result(target_root, with_agent:, mcp_status:)
      end

      def self.check_target!(target_root)
        raise UsageError.new(".textus/ already exists at #{target_root}") if File.directory?(target_root)
      end

      ASSET_ZONES = %w[raw].freeze

      def self.create_directories(target_root)
        FileUtils.mkdir_p(File.join(target_root, "schemas"))
        FileUtils.mkdir_p(File.join(target_root, "templates"))
        FileUtils.mkdir_p(File.join(target_root, "workflows"))
        ZONES.each do |z|
          dir = File.join(target_root, "data", z)
          FileUtils.mkdir_p(dir)
          File.write(File.join(dir, ".gitkeep"), "")
        end
        ASSET_ZONES.each do |z|
          dir = File.join(target_root, "assets", z)
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

      def self.write_gitignore(target_root)
        File.write(File.join(target_root, ".gitignore"), derived_gitignore(target_root))
      end

      def self.build_result(target_root, with_agent:, mcp_status:)
        result = { "protocol" => PROTOCOL, "initialized" => target_root, "profile" => with_agent ? "agent" : "default" }
        result["mcp_config"] = mcp_status if with_agent
        result
      end

      def self.manifest_yaml(with_agent:)
        return DEFAULT_MANIFEST unless with_agent

        base = YAML.safe_load(DEFAULT_MANIFEST)
        extra = YAML.safe_load(AGENT_ENTRIES)
        base["data"].merge!(extra["data"]) { |_lane, existing, added| existing + added }
        YAML.dump(base).sub(/\A---\n/, "")
      end

      def self.scaffold_agent_profile(target_root, scaffold_dir)
        {
          "project.schema.yaml" => File.join("schemas", "project.yaml"),
          "runbook.schema.yaml" => File.join("schemas", "runbook.yaml"),
          "orientation.erb" => File.join("templates", "orientation.erb"),
        }.each do |src, dest|
          File.write(File.join(target_root, dest), File.read(File.join(scaffold_dir, src)))
        end
      end

      def self.write_mcp_config(target_root, scaffold_dir)
        dest = File.join(File.dirname(target_root), ".mcp.json")
        return "skipped" if File.exist?(dest)

        File.write(dest, File.read(File.join(scaffold_dir, "mcp.json")))
        "written"
      end

      def self.derived_gitignore(target_root)
        manifest = Textus::Protocol::Manifest.load(target_root)
        root = Pathname.new(target_root)
        untracked = manifest.data.entries.reject(&:tracked?).map do |e|
          if e.nested?
            rel = e.path.start_with?("data/") ? e.path : File.join("data", e.path)
            "#{rel}/"
          else
            Pathname.new(Textus::Protocol::Key::Path.resolve(manifest.data, e)).relative_path_from(root).to_s
          end
        end
        Textus::Protocol::Layout.new(target_root).gitignore_body(untracked_entries: untracked)
      end
    end
  end
end
