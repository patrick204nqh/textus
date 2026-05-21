module Textus
  class Store
    class Reader
      def initialize(store)
        @store = store
        @manifest = store.manifest
      end

      def get(key)
        mentry, path, = @manifest.resolve(key)
        raise UnknownKey.new(key, suggestions: @manifest.suggestions_for(key)) unless File.exist?(path)

        raw = File.binread(path)
        parsed = Entry.for_format(mentry.format).parse(raw, path: path)
        meta = parsed["_meta"]
        content = parsed["content"]
        @store.send(:enforce_name_match!, path, meta, mentry.format)
        schema = @store.schema_for(mentry.schema)
        if schema
          case mentry.format
          when "markdown" then schema.validate!(meta)
          when "json", "yaml" then schema.validate!(content || {})
          end
        end
        Envelope.build(
          key: key, mentry: mentry, path: path,
          meta: meta, body: parsed["body"],
          etag: Etag.for_bytes(raw), content: content
        )
      end
    end
  end
end
