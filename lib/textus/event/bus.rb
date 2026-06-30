module Textus
  module Event
    class Bus
      def initialize
        @subscribers = Hash.new { |h, k| h[k] = [] }
      end

      def subscribe(event_class, &block)
        @subscribers[event_class] << block
        self
      end

      def emit(event)
        @subscribers[event.class].each { |sub| sub.call(event) }
      end
    end
  end
end
