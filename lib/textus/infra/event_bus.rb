module Textus
  module Infra
    class EventBus
      def initialize(registry:)
        @registry = registry
      end

      def publish(event, **payload)
        @registry.pubsub_handlers(event).each do |entry|
          entry[:callable].call(**payload)
        rescue StandardError => e
          warn "[textus] pub-sub handler #{entry[:name].inspect} for #{event.inspect} failed: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
