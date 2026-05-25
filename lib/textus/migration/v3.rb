module Textus
  module Migration
    module V3
      def self.run(root:, dry_run: false)
        manifest_path = File.join(root, ".textus/manifest.yaml")
        if File.exist?(manifest_path)
          original = File.read(manifest_path)
          rewritten = ManifestRewriter.rewrite(original)
          File.write(manifest_path, rewritten) unless dry_run
        end

        unless dry_run
          ZoneRenamer.run(root: root)
          FrontmatterSweeper.run(root: root)
          AuditRewriter.run(root: root)
        end

        hook_findings = HookDSLScanner.scan(root: root)

        { ok: true, hook_findings: hook_findings, dry_run: dry_run }
      end
    end
  end
end
