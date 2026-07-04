module Textus
  module Infra
    class Store
      class EntryIndex < Base
        def record(key:, lane:, format:, schema:, content:)
          table(:entries).insert_conflict(:replace).insert(
            key:, lane:, format:, schema:, content:,
            indexed_at: Time.now.utc
          )
        end

        def remove(key:)
          table(:entries).where(key:).delete
        end

        def search(query: nil, schema: nil, lane: nil, prefix: nil)
          dataset = table(:entries).select(:key, :lane, :format, :schema, :content, :indexed_at)
          if query
            match_query = query.to_s.gsub("-", " ")
            matching_rowids = @db[:entries_fts].where(Sequel.lit("entries_fts MATCH ?", match_query)).select_map(:rowid)
            dataset = dataset.where(Sequel[:entries][:rowid] => matching_rowids)
          end
          dataset = dataset.where(schema:) if schema
          dataset = dataset.where(lane:) if lane
          dataset = dataset.where(Sequel.like(:key, "#{prefix}%")) if prefix
          results(dataset.all)
        end
      end
    end
  end
end
