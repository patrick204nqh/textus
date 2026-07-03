module Textus
  module Infra
    class Store
      module Index
        class Builder
          def initialize(store:)
            @store = store
            @db = store.db
          end

          def rebuild!(resolver:)
            entry_index = Protocol::Index.new(@store.db)
            @db[:entries].each do |row|
              key = row[:key]
              mentry = resolver.resolve(key)
              next unless mentry

              entry = mentry.entry
              entry_index.record(
                key:, lane: entry.lane, format: entry.format,
                schema: entry.schema, content: row[:content]
              )
            end
          end
        end
      end
    end
  end
end
