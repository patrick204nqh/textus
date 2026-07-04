module Textus
  module Infra
    class Store
      class EntryStore
        def initialize(database, file_system)
          @db = database
          @fs = file_system
        end

        def read(key, manifest:, layout:)
          res = manifest.resolver.resolve(key)
          path = res.path
          return nil unless @fs.exists?(path)

          mentry = res.entry
          raw = @fs.read(path)
          parsed = Textus::Protocol::Format.for(mentry.format).parse(raw, path:)
          Textus::Value::Envelope.build(
            key:, mentry:, path:,
            meta: parsed["_meta"], body: parsed["body"],
            etag: Textus::Value::Etag.for_bytes(raw), content: parsed["content"]
          )
        end

        def exists?(key, manifest:)
          path = manifest.resolver.resolve(key).path
          @fs.exists?(path)
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

        def etag(path)
          Textus::Value::Etag.for_file(path)
        end

        def read_raw(path)
          @fs.read(path)
        end

        def write_raw(path, bytes)
          @fs.mkdir_p(File.dirname(path))
          @fs.write(path, bytes)
        end

        def delete_file(path)
          @fs.delete(path)
        end

        def move_file(from, to)
          @fs.mv(from, to)
        end

        def file_exists?(path)
          @fs.exists?(path)
        end
      end
    end
  end
end
