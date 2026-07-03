module Textus
  module Lanes
    module Artifact
      module Handlers
        def self.get(store, key)
          store.get(key:)
        end
  
        def self.list(store, prefix: nil)
          store.list(prefix: prefix || "artifact")
        end
  
        def self.status(store)
          store.list(prefix: "artifact").map do |row|
            cache = Cache.new(store)
            { key: row[:key], stale: cache.stale?(row[:key]) }
          end
        end
  
        def self.refresh(store, key)
          cache = Cache.new(store)
          cache.expire(key)
        end
      end
    end
  end
end
  