module Textus
  module Infra
    module Port
      # Persistence adapter for sentinel files. Owns the on-disk JSON shape, the
      # path layout (<store_root>/.run/sentinels/<target-rel-to-repo>.textus-managed.json
      # — runtime, git-ignored, ADR 0070), and all File/FileUtils I/O.
      # Core::Sentinel is a pure value object that depends on this port for
      # reads and writes.
      class SentinelStore
        module Interface
          def write!(target:, source:, store_root:) = raise NotImplementedError
          def load(path, repo_root) = raise NotImplementedError
          def sentinel_path(target, store_root) = raise NotImplementedError
          def targets_under(target_dir, store_root) = raise NotImplementedError
        end
        include Interface

        SUFFIX = ".textus-managed.json".freeze

        def initialize(file_system: Infra::FileStore.new)
          @file_system = file_system
        end

        def write!(target:, source:, store_root:)
          path = sentinel_path(target, store_root)
          @file_system.mkdir_p(File.dirname(path))
          repo_root = File.dirname(store_root)
          @file_system.write(path, JSON.generate(
                                     "source" => rel_or_abs(source, repo_root),
                                     "target" => rel_or_abs(target, repo_root),
                                     "sha256" => Digest::SHA256.hexdigest(@file_system.read(target)),
                                     "mode" => "copy",
                                   ))
        end

        def load(path, repo_root)
          raw = JSON.parse(@file_system.read(path))
          Textus::Infra::Port::Sentinel.new(
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
          File.join(Textus::Protocol::Layout.new(store_root).sentinels_root, rel + SUFFIX)
        end

        # Absolute target paths of every sentinel recorded under `target_dir`.
        def targets_under(target_dir, store_root)
          repo_root = File.dirname(store_root)
          rel = relative_to(target_dir, repo_root) or return []
          root = Textus::Protocol::Layout.new(store_root).sentinels_root
          sdir = File.join(root, rel)
          return [] unless @file_system.directory?(sdir)

          prefix = root + "/"
          @file_system.glob(File.join(sdir, "**", "*#{SUFFIX}")).map do |spath|
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
end
