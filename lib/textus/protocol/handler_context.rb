module Textus
  module Protocol
    module HandlerContextReadOps
      def read(key)
        entry_store.read(key)
      end

      def list(prefix: nil, lane: nil, q: nil, schema: nil)
        store.entry_index.search(query: q, schema:, lane:, prefix:)
      end

      def exists?(key)
        entry_store.exists?(key)
      end

      def resolve(key)
        @container.manifest.resolver.resolve(key)
      end

      def mentry_for(key)
        manifest.resolver.resolve(key).entry
      end
    end

    module HandlerContextWriteOps
      def write(key, mentry:, payload:, if_etag: nil, call: nil)
        entry_store.put(key, mentry:, payload:, if_etag:, call:)
      end

      def delete(key, if_etag: nil, call: nil)
        entry_store.delete(key, if_etag:, call:)
      end

      def move(from_key:, to_key:, new_mentry:, call: nil)
        entry_store.move(from_key:, to_key:, new_mentry:, call:)
      end
    end

    module HandlerContextSystem
      def manifest          = @container.manifest
      def layout            = @container.layout
      def schemas           = @container.schemas
      def workflows         = @container.workflows
      def workflow_registry = @container.workflow_registry
      def store             = @container.store
      attr_reader :container
    end

    class HandlerContext
      include HandlerContextReadOps
      include HandlerContextWriteOps
      include HandlerContextSystem

      def initialize(container)
        @container = container
        @entry_store = nil
      end

      def payload(meta: nil, body: nil, content: nil)
        Textus::Value::Payload.new(meta: meta || {}, body:, content:)
      end

      private

      def entry_store
        @entry_store ||= Protocol::EntryStore.new(
          file_system: store.file_system,
          manifest:,
          layout:,
          store:,
          workflow_registry:,
        )
      end
    end
  end
end
