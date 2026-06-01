module Textus
  module Hooks
    class Loader
      # A small DSL object passed to user hook blocks. Routes `.on(...)` to the
      # EventBus and `.rpc(...)` / `.register(...)` to the RpcRegistry.
      class Dsl
        def initialize(events:, rpc:)
          @events = events
          @rpc    = rpc
        end

        # Pubsub registration — delegates to EventBus.
        # Also handles RPC event names by delegating to RpcRegistry.
        def on(event, name, keys: nil, &)
          if Hooks::Catalog::RPC.key?(event.to_sym)
            @rpc.register(event, name, &)
          else
            @events.register(event, name, keys: keys, &)
          end
        end

        # Explicit RPC registration.
        def register(event, name, &)
          @rpc.register(event, name, &)
        end
      end

      def initialize(events:, rpc:)
        @events = events
        @rpc    = rpc
        @dsl    = Dsl.new(events: @events, rpc: @rpc)
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
          blk.call(@dsl)
        rescue StandardError, ScriptError => e
          raise UsageError.new("failed registering hook: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
