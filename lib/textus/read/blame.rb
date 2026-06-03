require "open3"

module Textus
  module Read
    # For one key, joins every audit-log row with the git commit (sha,
    # author, date, subject) that introduced the file state at that audit
    # row. Falls back to `git => nil` when not in a git repo or when the
    # file is untracked.
    class Blame
      extend Textus::Contract::DSL

      verb     :blame
      summary  "Annotate audit rows for a key with the git commit that introduced each file state."
      surfaces :cli, :ruby
      cli      "blame"
      arg :key,   String,  required: true, positional: true, description: "entry key to blame"
      arg :limit, Integer, required: false, description: "maximum number of audit rows to return"
      cli_response { |rows, inputs| { "verb" => "blame", "key" => inputs[:key], "rows" => rows } }

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @container = container
        @manifest  = container.manifest
        @root      = container.root
      end

      def call(key, limit: nil)
        audit_rows = Textus::Read::Audit.new(container: @container).call(key: key, limit: limit)
        path = resolve_path(key)
        return audit_rows.map { |r| r.merge("git" => nil) } unless git_tracked?(path)

        audit_rows.map { |r| r.merge("git" => git_commit_at(path, timestamp: r["ts"])) }
      end

      private

      def resolve_path(key)
        res = @manifest.resolver.resolve(key)
        mentry = res.entry
        path = res.path
        # Nested entries resolve to a file under the entry path; leaf entries
        # already have a fully-resolved path. Either way `path` is what git
        # needs to know about.
        path || Textus::Key::Path.resolve(@manifest.data, mentry)
      rescue Textus::Error
        nil
      end

      def git_tracked?(path)
        return false if path.nil?
        return false unless File.exist?(path)
        return false unless git_repo?

        _out, _err, status = Open3.capture3(
          "git", "ls-files", "--error-unmatch", path,
          chdir: @root
        )
        status.success?
      rescue Errno::ENOENT
        false
      end

      def git_repo?
        # Walk up from store root to find a .git directory.
        dir = @root
        loop do
          return true if File.directory?(File.join(dir, ".git"))

          parent = File.dirname(dir)
          return false if parent == dir

          dir = parent
        end
      end

      def git_commit_at(path, timestamp:)
        args = ["git", "log", "-1"]
        args << "--before=#{timestamp}" if timestamp
        args += ["--format=%H%x09%an%x09%aI%x09%s", "--", path]
        out, _err, status = Open3.capture3(*args, chdir: @root)
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
