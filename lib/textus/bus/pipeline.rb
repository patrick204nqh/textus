module Textus
  module Bus
    class Pipeline
      def initialize(registry:, middleware: [])
        @registry = registry
        @middleware = middleware
      end

      def dispatch(command, call:)
        stack = @middleware.reverse.reduce(->(cmd) { execute(cmd, call) }) do |next_mw, mw|
          ->(cmd) { mw.call(cmd, call, next_mw) }
        end
        stack.call(command)
      end

      private

      def execute(command, call)
        handler = @registry.for(command.class)
        handler.call(command, call)
      end
    end
  end
end
