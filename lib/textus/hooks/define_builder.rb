module Textus
  module Hooks
    class DefineBuilder
      EVENTS = Dsl::EVENTS

      def initialize(registry, name)
        @registry = registry
        @name = name
      end

      EVENTS.each do |event|
        define_method(event) do |**opts, &blk|
          @registry.register(event, @name, **opts, &blk)
        end
      end
    end
  end
end
