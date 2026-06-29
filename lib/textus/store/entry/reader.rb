module Textus
  class Store
    module Entry
      # Read-only counterpart to EnvelopeWriter. Resolves a key, reads the
      # bytes, parses them via the format strategy, and hands back an
      # Envelope. Used by Mv (pre-move inspection) and by EnvelopeWriter
      # (existing-meta lookup for the uid/sources preservation step in #put).
      #
      # No audit, no events, no permission checks — those live one layer up.
      class Reader
        def self.from(container:)
          # Prefer a cached reader on the container (injection point) for
          # tests and alternative runtimes. Fall back to constructing one.
          return container.reader if container.respond_to?(:reader) && container.reader

          new(file_store: container.file_store, manifest: container.manifest,
              layout: container.layout)
        end

        def initialize(file_store:, manifest:, layout:)
          @file_store = file_store
          @manifest   = manifest
          @layout     = layout
        end

        def read(key)
          res = @manifest.resolver.resolve(key)
          path = res.path
          return nil unless @file_store.exists?(path)

          mentry = res.entry
          raw = @file_store.read(path)
          parsed = Format.for(mentry.format).parse(raw, path: path)
          Textus::Value::Envelope.build(
            key: key, mentry: mentry, path: path,
            meta: parsed["_meta"], body: parsed["body"],
            etag: Value::Etag.for_bytes(raw), content: parsed["content"]
          )
        end

        def exists?(key)
          @file_store.exists?(@manifest.resolver.resolve(key).path)
        end
      end
    end
  end
end
