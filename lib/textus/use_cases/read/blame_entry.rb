module Textus
  module UseCases
    module Read
      module BlameEntry
        HANDLES = Dispatch::Contracts::BlameEntry
        NEEDS = %i[file_store manifest audit_log].freeze

        def self.call(command, call, deps)
          root = deps.manifest.data.root
          audit = UseCases::Read::AuditEntries.call(
            Data.define(:seq_since, :key, :lane, :role, :verb, :since, :correlation_id, :limit).new(
              seq_since: nil, key: command.key, lane: nil, role: call.role, verb: nil, since: nil, correlation_id: nil, limit: nil,
            ),
            call,
            deps,
          )
          return audit if audit.failure?

          audit_rows = audit.value || []

          path = resolve_path(command.key, deps)
          return Value::Result.success(audit_rows.map { |row| row.merge("git" => nil) }) unless git_tracked?(path, root: root)

          Value::Result.success(audit_rows.map { |row| row.merge("git" => git_commit_at(path, timestamp: row["ts"], root: root)) })
        end

        def self.resolve_path(key, deps)
          res = deps.manifest.resolver.resolve(key)
          path = res.path
          path || Textus::Key::Path.resolve(deps.manifest.data, res.entry)
        rescue Textus::Error
          nil
        end

        def self.git_tracked?(path, root:)
          return false if path.nil? || !File.exist?(path) || !git_repo?(root)

          _out, _err, status = Open3.capture3("git", "ls-files", "--error-unmatch", path, chdir: root)
          status.success?
        rescue Errno::ENOENT
          false
        end

        def self.git_repo?(root)
          dir = root
          loop do
            return true if File.directory?(File.join(dir, ".git"))

            parent = File.dirname(dir)
            return false if parent == dir

            dir = parent
          end
        end

        def self.git_commit_at(path, timestamp:, root:)
          args = ["git", "log", "-1"]
          args << "--before=#{timestamp}" if timestamp
          args += ["--format=%H%x09%an%x09%aI%x09%s", "--", path]
          out, _err, status = Open3.capture3(*args, chdir: root)
          return nil unless status.success?

          sha, author, date, subject = out.strip.split("\t", 4)
          return nil if sha.nil? || sha.empty?

          { "sha" => sha, "author" => author, "date" => date, "subject" => subject }
        rescue Errno::ENOENT
          nil
        end
      end
    end
  end
end
