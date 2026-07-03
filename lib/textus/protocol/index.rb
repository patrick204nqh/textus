module Textus
  module Protocol
    class Index
      def initialize(database)
        @db = database.respond_to?(:connection) ? database.connection : database
      end

      def record(key:, lane:, format:, schema:, content:)
        @db[:entries].insert_conflict(:replace).insert(
          key:, lane:, format:, schema:, content:,
          indexed_at: Time.now.utc
        )
      end

      def remove(key:)
        @db[:entries].where(key:).delete
      end

      def search(query:, schema:, lane:, prefix:)
        dataset = @db[:entries].select(:key, :lane, :format, :schema, :content, :indexed_at)
        if query
          match_query = query.to_s.gsub("-", " ")
          matching_rowids = @db[:entries_fts].where(Sequel.lit("entries_fts MATCH ?", match_query)).select_map(:rowid)
          dataset = dataset.where(Sequel[:entries][:rowid] => matching_rowids)
        end
        dataset = dataset.where(schema:) if schema
        dataset = dataset.where(lane:) if lane
        dataset = dataset.where(Sequel.like(:key, "#{prefix}%")) if prefix
        dataset.all.map { |row| row.transform_keys(&:to_s) }
      end
    end
  end
end
