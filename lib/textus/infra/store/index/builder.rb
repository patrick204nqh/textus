module Textus
  module Infra
    class Store
      module Index
        class Builder
          def initialize(db)
            @db = db
          end

          def rebuild!(resolver:)
            @db[:entries].each do |row|
              key = row[:key]
              mentry = resolver.resolve(key)
              next unless mentry

              entry = mentry.entry
              @db[:entries].insert_conflict(:replace).insert(
                key:, lane: entry.lane, format: entry.format,
                schema: entry.schema, content: row[:content],
                indexed_at: Time.now.utc
              )
            end
          end
        end
      end
    end
  end
end
