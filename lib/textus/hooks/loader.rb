module Textus
  module Hooks
    class Loader
      def initialize(bus:)
        @bus = bus
      end

      def load_dir(dir)
        return unless File.directory?(dir)

        # Discard any leftover blocks from a prior partial load.
        Textus.drain_hook_blocks

        Dir.glob(File.join(dir, "**/*.rb")).sort.each do |f| # rubocop:disable Lint/RedundantDirGlobSort
          load(f)
        rescue StandardError, ScriptError => e
          raise UsageError.new("failed loading hook #{File.basename(f)}: #{e.class}: #{e.message}")
        end

        Textus.drain_hook_blocks.each do |blk|
          blk.call(@bus)
        rescue StandardError, ScriptError => e
          raise UsageError.new("failed registering hook: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
