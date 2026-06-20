require "json"
require "digest"
require "fileutils"

module Textus
  module Ports
    # Persistence adapter for sentinel files. Owns the on-disk JSON shape, the
    # path layout (<store_root>/.run/sentinels/<target-rel-to-repo>.textus-managed.json
    # — runtime, git-ignored, ADR 0070), and all File/FileUtils I/O.
    # Core::Sentinel is a pure value object that depends on this port for
    # reads and writes.
    class SentinelStore
      SUFFIX = ".textus-managed.json".freeze

      def write!(target:, source:, store_root:)
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

      def load(path, repo_root)
        raw = JSON.parse(File.read(path))
        Textus::Core::Sentinel.new(
          target: absolutize(raw["target"], repo_root),
          source: absolutize(raw["source"], repo_root),
          sha256: raw["sha256"],
          mode: raw["mode"],
        )
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end

      def sentinel_path(target, store_root)
        repo_root = File.dirname(store_root)
        rel = relative_to(target, repo_root) || File.basename(target)
        File.join(StoreGeometry.new(store_root).sentinels_root, rel + SUFFIX)
      end

      # Absolute target paths of every sentinel recorded under `target_dir`.
      def targets_under(target_dir, store_root)
        repo_root = File.dirname(store_root)
        rel = relative_to(target_dir, repo_root) or return []
        root = StoreGeometry.new(store_root).sentinels_root
        sdir = File.join(root, rel)
        return [] unless File.directory?(sdir)

        prefix = root + "/"
        Dir.glob(File.join(sdir, "**", "*#{SUFFIX}")).map do |spath|
          # strip the sentinel-store prefix and the .textus-managed.json suffix to recover the repo-relative target path
          trel = spath.delete_prefix(prefix).delete_suffix(SUFFIX)
          File.join(repo_root, trel)
        end
      end

      private

      def rel_or_abs(path, repo_root)
        relative_to(path, repo_root) || File.expand_path(path)
      end

      def relative_to(path, repo_root)
        path = File.expand_path(path)
        base = File.expand_path(repo_root)
        return nil unless path.start_with?(base + File::SEPARATOR)

        path[(base.length + 1)..]
      end

      def absolutize(path, repo_root)
        return path if path.nil?
        return path if File.absolute_path?(path)

        File.expand_path(path, repo_root)
      end
    end
  end
end
