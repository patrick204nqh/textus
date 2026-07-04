module Textus
  module Lanes
    module Artifact
      class Cache
        def initialize(store, ttl_default: 3600 * 24 * 30)
          @store = store
          @ttl_default = ttl_default
        end

        def ttl(key)
          entry = @store.get(key:)
          return @ttl_default unless entry

          entry["ttl"] || @ttl_default
        end

        def stale?(key)
          entry = @store.get(key:)
          return true unless entry
          return true if entry["stale"] || entry["fetching"]

          generated_at = entry["generated_at"]
          return true unless generated_at

          age = Time.now - Time.parse(generated_at)
          age > ttl(key)
        end

        def expire(key)
          @store.put(key:, meta: { "stale" => true })
        end
      end
    end
  end
end
