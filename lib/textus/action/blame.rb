# frozen_string_literal: true

require "open3"

module Textus
  module Action
    class Blame < Base
      extend Textus::Contract::DSL

      verb :blame
      summary "Annotate audit rows for a key with the git commit that introduced each file state."
      surfaces :cli
      cli "blame"
      arg :key, String, required: true, positional: true, description: "entry key to blame"
      arg :limit, Integer, required: false, description: "maximum number of audit rows to return"
      view(:cli) { |rows, inputs| { "verb" => "blame", "key" => inputs[:key], "rows" => rows } }


      def initialize(key:, limit: nil)
        super()
        @key = key
        @limit = limit
      end

      def call(container:, **)
        @container = container
        @manifest = container.manifest
        @root = container.root

        audit_rows = Textus::Action::Audit.new(key: @key, limit: @limit).call(container: container)
        path = resolve_path(@key)
        return audit_rows.map { |row| row.merge("git" => nil) } unless git_tracked?(path)

        audit_rows.map { |row| row.merge("git" => git_commit_at(path, timestamp: row["ts"])) }
      end

      def self.new(*args, **kwargs)
        return super(**kwargs) unless args.any?

        positional = instance_method(:initialize).parameters.slice(:keyreq, :key).map(&:last)
        mapped = positional.zip(args).to_h
        super(**mapped.merge(kwargs))
      end

      private

      def resolve_path(key)
        res = @manifest.resolver.resolve(key)
        mentry = res.entry
        path = res.path
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
