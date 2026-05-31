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
  end
end
