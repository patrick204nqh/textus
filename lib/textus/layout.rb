require "fileutils"

module Textus
  # Single source of truth for every path textus owns under a store root.
  # All disposable runtime state nests under <root>/.run/ so the
  # tracked/disposable boundary is a directory boundary. ADR 0038.
  module Layout
    RUN = ".run"

    def self.run(root)
      File.join(root, RUN)
    end

    def self.state(root)
      File.join(run(root), "state")
    end

    def self.cursor(root, role)
      File.join(state(root), "cursor.#{role}")
    end

    def self.locks(root)
      File.join(run(root), "locks")
    end

    def self.build_lock(root)
      File.join(run(root), "build.lock")
    end

    def self.audit_dir(root)
      File.join(run(root), "audit")
    end

    def self.audit_log(root)
      File.join(audit_dir(root), "audit.log")
    end

    GITIGNORE = <<~GITIGNORE
      # textus runtime artifacts — safe to delete, never commit
      #{RUN}/
    GITIGNORE

    # One-time, idempotent: move a pre-0038 store's runtime files under .run/.
    # No-op once .run/ holds them. Never touches .build.lock (ephemeral).
    def self.migrate_legacy!(root)
      relocate_audit(root)
      relocate_dir(File.join(root, ".state"), state(root))
      relocate_dir(File.join(root, ".locks"), locks(root))
    end

    def self.relocate_audit(root)
      legacy = Dir.glob(File.join(root, "audit.log*"))
      return if legacy.empty?
      return if File.directory?(audit_dir(root)) # already migrated

      FileUtils.mkdir_p(audit_dir(root))
      legacy.each { |src| FileUtils.mv(src, File.join(audit_dir(root), File.basename(src))) }
    end

    def self.relocate_dir(legacy_dir, target_dir)
      return unless File.directory?(legacy_dir)
      return if File.directory?(target_dir)

      FileUtils.mkdir_p(File.dirname(target_dir))
      FileUtils.mv(legacy_dir, target_dir)
    end

    private_class_method :relocate_audit, :relocate_dir
  end
end
