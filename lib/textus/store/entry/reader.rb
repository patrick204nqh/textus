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
        def initialize(file_system:, manifest:, layout:)
          @file_system = file_system
          @manifest   = manifest
          @layout     = layout
        end

        def read(key)
          res = @manifest.resolver.resolve(key)
          path = res.path
          return nil unless @file_system.exists?(path)

          mentry = res.entry
          raw = @file_system.read(path)
          parsed = Format.for(mentry.format).parse(raw, path: path)
          Textus::Value::Envelope.build(
            key: key, mentry: mentry, path: path,
            meta: parsed["_meta"], body: parsed["body"],
            etag: Value::Etag.for_bytes(raw), content: parsed["content"]
          )
        end

        def exists?(key)
          @file_system.exists?(@manifest.resolver.resolve(key).path)
        end
      end
    end
  end
end
