module Textus
  module Artifact
    class Lifecycle
      def initialize(cache)
        @cache = cache
      end

      def on_stale(key)
        @cache.expire(key)
      end

      def on_expire(key)
        @cache.expire(key)
      end

      def retention(key)
        @cache.ttl(key)
      end
    end
  end
end
