module Textus
  class Store
    class Reader
      def initialize(store)
        @store = store
        @manifest = store.manifest
      end

      def get(key)
        read_raw_envelope(key) || raise(UnknownKey.new(key, suggestions: @manifest.suggestions_for(key)))
      end

      # Reads the current on-disk state of key as a bare envelope, skipping
      # freshness annotation to avoid recursion. Used by Freshness.refresh_sync
      # after a sync refresh completes.
      def read_raw_envelope(key)
        res = @manifest.resolve(key)
        mentry = res.entry
        path = res.path
        return nil unless File.exist?(path)

        raw = File.binread(path)
        parsed = Entry.for_format(mentry.format).parse(raw, path: path)
        Envelope.build(
          key: key, mentry: mentry, path: path,
          meta: parsed["_meta"], body: parsed["body"],
          etag: Etag.for_bytes(raw), content: parsed["content"]
        )
      end

      def list(prefix: nil, zone: nil)
        rows = @manifest.enumerate(prefix: prefix)
        rows = rows.select { |r| r[:manifest_entry].zone == zone } if zone
        rows.map { |row| { "key" => row[:key], "zone" => row[:manifest_entry].zone, "path" => row[:path] } }
      end

      def where(key)
        res = @manifest.resolve(key)
        mentry = res.entry
        path = res.path
        { "protocol" => PROTOCOL, "key" => key, "zone" => mentry.zone, "owner" => mentry.owner, "path" => path }
      end

      def schema_envelope(key)
        mentry = @manifest.resolve(key).entry
        schema = @store.schema_for(mentry.schema)
        { "protocol" => PROTOCOL, "key" => key, "schema_ref" => mentry.schema, "schema" => schema&.to_h }
      end

      # Returns the Textus UID for a key (or nil if the entry has none yet).
      # Raises UnknownKey if the key doesn't resolve to a real file.
      def uid(key)
        get(key).uid
      end

      def deps(key)   = Dependencies.deps_of(@manifest, key)
      def rdeps(key)  = Dependencies.rdeps_of(@manifest, key)
      def published   = Dependencies.published_of(@manifest)

      def stale(prefix: nil, zone: nil)
        Staleness.new(manifest: @manifest).call(prefix: prefix, zone: zone)
      end

      def validate_all
        Validator.new(
          reader: self, manifest: @manifest,
          audit_log: @store.audit_log,
          schema_for: ->(name) { @store.schema_for(name) }
        ).call
      end
    end
  end
end
