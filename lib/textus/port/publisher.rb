require "fileutils"

module Textus
  module Port
    # Publishes built artifacts from the store to repo-relative consumer paths.
    # Publish = copy + sentinel. The in-store file is already the consumer-shaped
    # artifact; no parsing or stripping.
    #
    # Sentinel I/O is delegated to Textus::Port::SentinelStore. Sentinels live
    # under `<store_root>/.run/sentinels/` (runtime, git-ignored — ADR 0070) and
    # mirror the target's repo-relative layout so consumer directories aren't
    # polluted with `.textus-managed.json` siblings.
    #
    # An instantiable class (ADR 0109).
    class Publisher
      module Interface
        def publish(source:, target:, store_root:, provenance_source: nil) = raise NotImplementedError
        def unpublish(target:, store_root:) = raise NotImplementedError
      end
      include Interface

      def initialize(file_system: Infra::FileStore.new)
        @file_system = file_system
      end

      def publish(source:, target:, store_root:, provenance_source: source)
        @file_system.mkdir_p(File.dirname(target))
        guard_clobber(source, target, store_root)
        @file_system.delete(target) if @file_system.symlink?(target)
        @file_system.copy(source, target)
        Textus::Port::SentinelStore.new(file_system: @file_system).write!(target: target, source: provenance_source, store_root: store_root)
      end

      # Removes a previously-published file and its sentinel. No-op unless the
      # target is textus-managed — never deletes an unmanaged file.
      def unpublish(target:, store_root:)
        return unless managed?(target, store_root)

        @file_system.delete(target)
        sentinel = Textus::Port::SentinelStore.new(file_system: @file_system).sentinel_path(target, store_root)
        @file_system.delete(sentinel)
      end

      private

      # Refuse to clobber an unmanaged target — EXCEPT adopt one whose bytes
      # already equal the source (ADR 0050: a migration copies files into the
      # store and publishes them back to where they already live, so the target
      # is byte-identical — nothing is at risk). Adoption writes no sentinel
      # here; the normal publish path below does, and the cp is a content no-op.
      # An unmanaged target whose content DIFFERS, or any unmanaged symlink, is
      # still refused — that is the guard's real job.
      def guard_clobber(source, target, store_root)
        return unless @file_system.exists?(target) || @file_system.symlink?(target)
        return if managed?(target, store_root)
        return if adoptable?(source, target)

        raise PublishError.new("refusing to clobber unmanaged file at #{target}", target: target)
      end

      def adoptable?(source, target)
        !@file_system.symlink?(target) && File.file?(target) && @file_system.identical?(source, target)
      end

      def managed?(target, store_root)
        @file_system.exists?(Textus::Port::SentinelStore.new(file_system: @file_system).sentinel_path(target, store_root))
      end
    end
  end
end
