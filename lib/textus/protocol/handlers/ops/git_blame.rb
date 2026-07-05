require "open3"

module Textus
  module Protocol
    module Handlers
      module Ops
        class GitBlame
          def call(key:, ctx:)
            root = ctx.manifest.data.root
            path = resolve_blame_path(key, ctx)
            return nil unless path && git_tracked?(path, root:)

            audit_rows = ctx.audit_log.list(key:)
            audit_rows.each_with_object({}) { |row, h| h[row["ts"]] = git_commit_at(path, timestamp: row["ts"], root:) }
          end

          private

          def resolve_blame_path(key, ctx)
            res = ctx.resolve(key:)
            res.path || Textus::Protocol::Key::Path.resolve(ctx.manifest.data, res.entry)
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
  end
end
