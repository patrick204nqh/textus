module Textus
  module Envelope
    # Read-only counterpart to EnvelopeWriter. Resolves a key, reads the
    # bytes, parses them via the format strategy, and hands back an
    # Envelope. Used by Mv (pre-move inspection) and by EnvelopeWriter
    # (existing-uid lookup for the uid-preservation step in #put).
    #
    # No audit, no events, no permission checks — those live one layer up.
    class Reader
      def self.from(container:)
        new(file_store: container.file_store, manifest: container.manifest)
      end

      def initialize(file_store:, manifest:)
        @file_store = file_store
        @manifest   = manifest
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

      def existing_uid(key)
        env = read(key)
        env&.uid
      rescue StandardError
        nil
      end

      def exists?(key)
        @file_store.exists?(@manifest.resolver.resolve(key).path)
      end
    end
  end
end
