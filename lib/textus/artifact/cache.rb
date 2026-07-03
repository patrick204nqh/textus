module Textus
  module Artifact
    class Cache
      def initialize(store, ttl_default: 3600 * 24 * 30)
        @store = store
        @ttl_default = ttl_default
      end

      def ttl(key)
        entry = @store.get(key:)
        return @ttl_default unless entry&.freshness

        entry.freshness["ttl"] || @ttl_default
      end

      def stale?(key)
        entry = @store.get(key:)
        return true unless entry

        age = Time.now - (entry.freshness&.dig("generated_at")&.then { |t| Time.parse(t) } || Time.at(0))
        age > ttl(key)
      rescue StandardError
        true
      end

      def expire(key)
        @store.put(key:, meta: { "stale" => true })
      end
    end
  end
end
