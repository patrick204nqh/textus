module Textus
  class HandlerRegistry
    def initialize
      @handlers = {}
    end

    def register(command_class, handler)
      @handlers[command_class] = handler
    end

    def for(command_class)
      @handlers[command_class] || raise("no handler registered for #{command_class}")
    end

    def registered?(command_class)
      @handlers.key?(command_class)
    end
  end
end
