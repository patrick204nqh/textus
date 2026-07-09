module Textus
  module Lanes
    module Artifact
      module Handlers
        module_function

        def get(key:, store:, ctx:, call:)
          store.get(key:)
        end

        def list(store:, ctx:, call:, under: nil)
          store.list(under: prefix || "artifact")
        end

        def status(store:, ctx:, call:)
          store.list(under: "artifact").map do |row|
            cache = Cache.new(store)
            { key: row[:key], stale: cache.stale?(row[:key]) }
          end
        end

        def refresh(key:, store:, ctx:, call:)
          cache = Cache.new(store)
          cache.expire(key)
        end
      end
    end
  end
end
