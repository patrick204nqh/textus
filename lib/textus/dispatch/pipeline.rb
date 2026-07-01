module Textus
  module Dispatch
    class Pipeline
      attr_reader :container

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

      def self.build_command(contract_class, inputs)
        members = contract_class.members
        kwargs = members.to_h do |member|
          [member, inputs[member]]
        end
        contract_class.new(**kwargs)
      end

      private

      def execute(command, call)
        handler = @registry.for(command.class)
        handler.call(command: command, call: call)
      end
    end
  end
end
