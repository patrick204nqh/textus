module Textus
  module Protocol
    class EntryStore
      def initialize(file_system:, manifest:, layout:, audit_log: nil, entry_index: nil, store: nil, workflow_registry: nil)
        @file_system = file_system
        @manifest = manifest
        @store = store
        @layout = layout
        @workflow_registry = workflow_registry
        # Allow backward compat construction without store
        @audit_log = audit_log || store&.event_store
        @entry_index = entry_index || store&.entry_store
      end

      def read(key)
        res = @manifest.resolver.resolve(key)
        path = res.path
        return nil unless @file_system.exists?(path)

        mentry = res.entry
        raw = @file_system.read(path)
        parsed = Textus::Protocol::Format.for(mentry.format).parse(raw, path: path)
        Textus::Protocol::Envelope.build(
          key:, mentry:, path:,
          meta: parsed["_meta"], body: parsed["body"],
          etag: Textus::Value::Etag.for_bytes(raw), content: parsed["content"]
        )
      end

      def exists?(key)
        @file_system.exists?(@manifest.resolver.resolve(key).path)
      end

      def put(key, if_etag: nil, mentry: nil, payload: nil, call: nil, **)
        Textus::Protocol::WritePipeline.put(key, mentry:, payload:, call:, if_etag:,
                                                 file_system: @file_system, manifest: @manifest, store: @store,
                                                 layout: @layout, reader: self, workflow_registry: @workflow_registry)
      end

      def delete(key, if_etag: nil, call: nil, mentry: nil, **)
        Textus::Protocol::WritePipeline.delete(key, call:, mentry:, if_etag:,
                                                    file_system: @file_system, manifest: @manifest, store: @store,
                                                    layout: @layout, reader: self, workflow_registry: @workflow_registry)
      end

      def move(from_key: nil, to_key: nil, new_mentry: nil, call: nil, if_etag: nil, **)
        Textus::Protocol::WritePipeline.move(from_key:, to_key:, new_mentry:, call:, if_etag:,
                                             file_system: @file_system, manifest: @manifest, store: @store,
                                             layout: @layout, reader: self, workflow_registry: @workflow_registry)
      end
    end
  end
end
