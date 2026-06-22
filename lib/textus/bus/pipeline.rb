module Textus
  module Bus
    class Pipeline
      def initialize(registry:, container:, middleware: [])
        @registry = registry
        @middleware = middleware
        @container = container
      end

      def dispatch(command, call:)
        stack = @middleware.reverse.reduce(->(cmd, c) { execute(cmd, c) }) do |next_mw, mw|
          ->(cmd, c) { mw.call(container: @container, command: cmd, call: c, next_handler: next_mw) }
        end
        stack.call(command, call)
      end

      private

      def execute(command, call)
        handler = @registry.for(command.class)
        handler.call(command, call)
      end
    end
  end
end
