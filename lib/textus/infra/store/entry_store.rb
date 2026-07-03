module Textus
  module Infra
  class Store
    class EntryStore
      def initialize(file_system:, manifest:, audit_log:, layout:, entry_index:)
        @file_system = file_system
        @manifest = manifest
        @audit_log = audit_log
        @layout = layout
        @entry_index = entry_index
      end

      def read(key)
        res = @manifest.resolver.resolve(key)
        path = res.path
        return nil unless @file_system.exists?(path)

        mentry = res.entry
        raw = @file_system.read(path)
        parsed = Textus::Protocol::Format.for(mentry.format).parse(raw, path: path)
        Textus::Value::Envelope.build(
          key:, mentry:, path:,
          meta: parsed["_meta"], body: parsed["body"],
          etag: Textus::Value::Etag.for_bytes(raw), content: parsed["content"]
        )
      end

      def exists?(key)
        @file_system.exists?(@manifest.resolver.resolve(key).path)
      end

      def put(key, if_etag: nil, mentry: nil, payload: nil, call: nil, **)
        WritePipeline.put(key, mentry:, payload:, call:, if_etag:, file_system: @file_system, manifest: @manifest, audit_log: @audit_log,
                               layout: @layout, reader: self, entry_index: @entry_index)
      end

      def delete(key, if_etag: nil, call: nil, mentry: nil, **)
        WritePipeline.delete(key, call:, mentry:, if_etag:, file_system: @file_system, manifest: @manifest, audit_log: @audit_log,
                                  layout: @layout, reader: self, entry_index: @entry_index)
      end

      def move(from_key: nil, to_key: nil, new_mentry: nil, call: nil, if_etag: nil, **)
        WritePipeline.move(from_key:, to_key:, new_mentry:, call:, if_etag:, file_system: @file_system, manifest: @manifest,
                           audit_log: @audit_log, layout: @layout, reader: self, entry_index: @entry_index)
      end
    end
  end
  end
end
