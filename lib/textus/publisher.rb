require "json"
require "digest"
require "fileutils"

module Textus
  # Publishes built artifacts from the store to repo-relative consumer paths.
  # Publish = copy + sentinel. The in-store file is already the consumer-shaped
  # artifact; no parsing or stripping. Sentinels live under
  # `<store_root>/sentinels/` and mirror the target's repo-relative layout so
  # consumer directories aren't polluted with `.textus-managed.json` siblings.
  module Publisher
    SENTINEL_SUFFIX = ".textus-managed.json".freeze
    SENTINEL_DIR    = "sentinels".freeze

    def self.publish(source:, target:, store_root:)
      FileUtils.mkdir_p(File.dirname(target))
      refuse_if_unmanaged(target, store_root)
      File.delete(target) if File.symlink?(target)
      FileUtils.cp(source, target)
      write_sentinel(target, store_root: store_root, source: source)
      cleanup_legacy_sentinel(target)
    end

    def self.refuse_if_unmanaged(target, store_root)
      return unless File.exist?(target) || File.symlink?(target)
      return if managed?(target, store_root)

      raise PublishError.new("refusing to clobber unmanaged file at #{target}")
    end

    def self.managed?(target, store_root)
      File.exist?(sentinel_path(target, store_root)) || File.exist?(legacy_sentinel_path(target))
    end

    def self.write_sentinel(target, store_root:, source:)
      path = sentinel_path(target, store_root)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.generate(
                         "source" => source,
                         "target" => target,
                         "sha256" => Digest::SHA256.hexdigest(File.binread(target)),
                         "mode" => "copy",
                       ))
    end

    # Sentinel layout: <store_root>/sentinels/<target_rel_to_repo>.textus-managed.json
    # The full target extension is preserved so a marketplace.json and
    # marketplace.yaml don't collide.
    def self.sentinel_path(target, store_root)
      repo_root = File.dirname(store_root)
      rel = relative_to(target, repo_root) || File.basename(target)
      File.join(store_root, SENTINEL_DIR, rel + SENTINEL_SUFFIX)
    end

    def self.legacy_sentinel_path(target)
      target + SENTINEL_SUFFIX
    end

    def self.cleanup_legacy_sentinel(target)
      FileUtils.rm_f(legacy_sentinel_path(target))
    end

    def self.relative_to(path, base)
      path = File.expand_path(path)
      base = File.expand_path(base)
      return nil unless path.start_with?(base + File::SEPARATOR)

      path[(base.length + 1)..]
    end
  end
end
