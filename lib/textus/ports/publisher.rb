require "fileutils"

module Textus
  module Ports
    # Publishes built artifacts from the store to repo-relative consumer paths.
    # Publish = copy + sentinel. The in-store file is already the consumer-shaped
    # artifact; no parsing or stripping.
    #
    # Sentinel I/O is delegated to Textus::Ports::SentinelStore. Sentinels live
    # under `<store_root>/sentinels/` and mirror the target's repo-relative layout
    # so consumer directories aren't polluted with `.textus-managed.json` siblings.
    module Publisher
      def self.publish(source:, target:, store_root:)
        FileUtils.mkdir_p(File.dirname(target))
        refuse_if_unmanaged(target, store_root)
        File.delete(target) if File.symlink?(target)
        FileUtils.cp(source, target)
        Textus::Ports::SentinelStore.new.write!(target: target, source: source, store_root: store_root)
      end

      # Removes a previously-published file and its sentinel. No-op unless the
      # target is textus-managed — never deletes an unmanaged file.
      def self.unpublish(target:, store_root:)
        return unless managed?(target, store_root)

        FileUtils.rm_f(target)
        sentinel = Textus::Ports::SentinelStore.new.sentinel_path(target, store_root)
        FileUtils.rm_f(sentinel)
      end

      def self.refuse_if_unmanaged(target, store_root)
        return unless File.exist?(target) || File.symlink?(target)
        return if managed?(target, store_root)

        raise PublishError.new("refusing to clobber unmanaged file at #{target}", target: target)
      end

      def self.managed?(target, store_root)
        File.exist?(Textus::Ports::SentinelStore.new.sentinel_path(target, store_root))
      end
    end
  end
end
