require "fileutils"

module Textus
  module Infra
    # Publishes built artifacts from the store to repo-relative consumer paths.
    # Publish = copy + sentinel. The in-store file is already the consumer-shaped
    # artifact; no parsing or stripping.
    #
    # Sentinel I/O is delegated to Textus::Domain::Sentinel. Sentinels live under
    # `<store_root>/sentinels/` and mirror the target's repo-relative layout so
    # consumer directories aren't polluted with `.textus-managed.json` siblings.
    module Publisher
      def self.publish(source:, target:, store_root:)
        FileUtils.mkdir_p(File.dirname(target))
        refuse_if_unmanaged(target, store_root)
        File.delete(target) if File.symlink?(target)
        FileUtils.cp(source, target)
        Textus::Domain::Sentinel.write!(target: target, source: source, store_root: store_root)
      end

      def self.refuse_if_unmanaged(target, store_root)
        return unless File.exist?(target) || File.symlink?(target)
        return if managed?(target, store_root)

        raise PublishError.new("refusing to clobber unmanaged file at #{target}", target: target)
      end

      def self.managed?(target, store_root)
        File.exist?(Textus::Domain::Sentinel.sentinel_path(target, store_root))
      end
    end
  end
end
