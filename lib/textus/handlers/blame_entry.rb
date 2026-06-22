module Textus
  module Handlers
    class BlameEntry
      def initialize(manifest:, audit_log:)
        @manifest = manifest
        @audit_log = audit_log
      end

      def call(command, call)
        root = @manifest.data.root
        audit_handler = Handlers::AuditEntries.new(manifest: @manifest, audit_log: @audit_log)
        audit_q = Struct.new(:key, :limit, :seq_since, :lane, :role, :verb, :since, :correlation_id, keyword_init: true)
        audit_result = audit_handler.call(audit_q.new(key: command.key, limit: command.limit), call)
        audit_rows = audit_result.value || []

        path = resolve_path(command.key)
        return Result.success(audit_rows.map { |row| row.merge("git" => nil) }) unless git_tracked?(path, root: root)

        Result.success(audit_rows.map { |row| row.merge("git" => git_commit_at(path, timestamp: row["ts"], root: root)) })
      end

      private

      def resolve_path(key)
        res = @manifest.resolver.resolve(key)
        path = res.path
        path || Textus::Key::Path.resolve(@manifest.data, res.entry)
      rescue Textus::Error
        nil
      end

      def git_tracked?(path, root:)
        return false if path.nil? || !File.exist?(path) || !git_repo?(root)

        _out, _err, status = Open3.capture3("git", "ls-files", "--error-unmatch", path, chdir: root)
        status.success?
      rescue Errno::ENOENT
        false
      end

      def git_repo?(root)
        dir = root
        loop do
          return true if File.directory?(File.join(dir, ".git"))
          parent = File.dirname(dir)
          return false if parent == dir
          dir = parent
        end
      end

      def git_commit_at(path, timestamp:, root:)
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
