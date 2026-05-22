module Textus
  module Infra
    class EventBus
      def initialize(registry:)
        @registry = registry
      end

      def publish(event, **payload)
        @registry.pubsub_handlers(event).each do |entry|
          next unless entry[:keys].nil? || matches?(entry[:keys], payload[:key])

          entry[:callable].call(**payload)
        rescue StandardError => e
          warn "[textus] pub-sub handler #{entry[:name].inspect} for #{event.inspect} failed: #{e.class}: #{e.message}"
        end
      end

      private

      def matches?(globs, key)
        return true if key.nil?

        Array(globs).any? { |g| File.fnmatch?(g, key.to_s, File::FNM_PATHNAME) }
      end
    end
  end
end
