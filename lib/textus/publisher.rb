require "json"
require "digest"
require "fileutils"

module Textus
  # Publishes built artifacts from the store to repo-relative consumer paths.
  # Publish = copy + sentinel. The in-store file is already the consumer-shaped
  # artifact; no parsing or stripping. A sidecar `.textus-managed.json` marks
  # the target as textus-owned so future republishes don't clobber user files.
  module Publisher
    def self.publish(source:, target:)
      FileUtils.mkdir_p(File.dirname(target))
      refuse_if_unmanaged(target)
      # Clear a managed legacy symlink (or any managed target) before copying so
      # FileUtils.cp writes a real file at `target` rather than following a link.
      File.delete(target) if File.symlink?(target)
      FileUtils.cp(source, target)
      write_sentinel(target, source: source)
    end

    def self.refuse_if_unmanaged(target)
      return unless File.exist?(target) || File.symlink?(target)
      return if managed?(target)

      raise PublishError.new("refusing to clobber unmanaged file at #{target}")
    end

    def self.managed?(target)
      File.exist?(sentinel_path(target))
    end

    def self.write_sentinel(target, source:)
      File.write(sentinel_path(target), JSON.generate(
                                          "source" => source,
                                          "sha256" => Digest::SHA256.hexdigest(File.binread(target)),
                                          "mode" => "copy",
                                        ))
    end

    def self.sentinel_path(target)
      target + ".textus-managed.json"
    end
  end
end
