module Textus
  module Hooks
    module Dsl
      def on(event, name, **, &blk)
        raise UsageError.new("hook needs a block") unless blk

        Loader.current_registry.register(event, name, **, &blk)
      end
    end
  end
end
