# frozen_string_literal: true

require "open3"

module Textus
  module Action
    class Blame < Base
      verb :blame
      summary "Annotate audit rows for a key with the git commit that introduced each file state."
      surfaces :cli
      cli "blame"
      arg :key, String, required: true, positional: true, description: "entry key to blame"
      arg :limit, Integer, required: false, description: "maximum number of audit rows to return"
      view(:cli) { |rows, inputs| { "verb" => "blame", "key" => inputs[:key], "rows" => rows } }

      def self.call(container:, key:, limit: nil, **)
        manifest = container.manifest
        root = container.root

        audit_rows = Textus::Action::Audit.call(container: container, key: key, limit: limit)
        path = resolve_path(key, manifest: manifest)
        return audit_rows.map { |row| row.merge("git" => nil) } unless git_tracked?(path, root: root)

        audit_rows.map { |row| row.merge("git" => git_commit_at(path, timestamp: row["ts"], root: root)) }
      end

      def self.resolve_path(key, manifest:)
        res = manifest.resolver.resolve(key)
        mentry = res.entry
        path = res.path
        path || Textus::Key::Path.resolve(manifest.data, mentry)
      rescue Textus::Error
        nil
      end

      def self.git_tracked?(path, root:)
        return false if path.nil?
        return false unless File.exist?(path)
        return false unless git_repo?(root)

        _out, _err, status = Open3.capture3(
          "git", "ls-files", "--error-unmatch", path,
          chdir: root
        )
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
