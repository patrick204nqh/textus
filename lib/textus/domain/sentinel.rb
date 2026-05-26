require "json"
require "digest"
require "fileutils"

module Textus
  module Domain
    # Value object for sentinel files written by Infra::Publisher and inspected
    # by Doctor::Check::Sentinels. Owns the JSON shape ({source, target,
    # sha256, mode}) and the on-disk path layout (<store_root>/sentinels/
    # <target-rel-to-repo>.textus-managed.json). Target/source are repo-relative
    # when the published file is under the repo root, absolute otherwise.
    class Sentinel
      SUFFIX = ".textus-managed.json".freeze
      DIR    = "sentinels".freeze

      attr_reader :target, :source, :sha256, :mode

      def self.write!(target:, source:, store_root:)
        path = sentinel_path(target, store_root)
        FileUtils.mkdir_p(File.dirname(path))
        repo_root = File.dirname(store_root)
        File.write(path, JSON.generate(
                           "source" => rel_or_abs(source, repo_root),
                           "target" => rel_or_abs(target, repo_root),
                           "sha256" => Digest::SHA256.hexdigest(File.binread(target)),
                           "mode" => "copy",
                         ))
      end

      def self.load(path, repo_root)
        raw = JSON.parse(File.read(path))
        new(
          target: absolutize(raw["target"], repo_root),
          source: absolutize(raw["source"], repo_root),
          sha256: raw["sha256"],
          mode: raw["mode"],
        )
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end

      def self.sentinel_path(target, store_root)
        repo_root = File.dirname(store_root)
        rel = relative_to(target, repo_root) || File.basename(target)
        File.join(store_root, DIR, rel + SUFFIX)
      end

      def self.rel_or_abs(path, repo_root)
        relative_to(path, repo_root) || File.expand_path(path)
      end

      def self.relative_to(path, repo_root)
        path = File.expand_path(path)
        base = File.expand_path(repo_root)
        return nil unless path.start_with?(base + File::SEPARATOR)

        path[(base.length + 1)..]
      end

      def self.absolutize(path, repo_root)
        return path if path.nil?
        return path if File.absolute_path?(path)

        File.expand_path(path, repo_root)
      end

      def initialize(target:, source:, sha256:, mode:)
        @target = target
        @source = source
        @sha256 = sha256
        @mode = mode
      end

      def orphan?
        @target.nil? || !File.exist?(@target)
      end

      def drift?
        return false if orphan?
        return false if @sha256.nil?

        Digest::SHA256.hexdigest(File.binread(@target)) != @sha256
      end
    end
  end
end
