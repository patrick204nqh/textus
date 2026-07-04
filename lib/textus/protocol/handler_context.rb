module Textus
  module Protocol
    class HandlerContext
      def initialize(container)
        @container = container
        @entry_store = nil
      end

      def store = @container.store

      # Reading
      def read(key)
        entry_store.read(key)
      end

      def list(prefix: nil, lane: nil, q: nil, schema: nil)
        store.entry_store.search(query: q, schema:, lane:, prefix:)
      end

      def exists?(key)
        entry_store.exists?(key)
      end

      def resolve(key)
        @container.manifest.resolver.resolve(key)
      end

      # Writing
      def write(key, mentry:, payload:, if_etag: nil, call: nil)
        entry_store.put(key, mentry:, payload:, if_etag:, call:)
      end

      def delete(key, if_etag: nil, mentry: nil, call: nil)
        entry_store.delete(key, if_etag:, mentry:, call:)
      end

      def move(from_key:, to_key:, new_mentry:, call: nil)
        entry_store.move(from_key:, to_key:, new_mentry:, call:)
      end

      # Query
      def manifest   = @container.manifest
      def layout     = @container.layout
      def schemas    = @container.schemas
      def workflows  = @container.workflows
      attr_reader :container

      def file_system = store.file_system
      def audit       = store.event_store
      def links       = store.link_store
      def event_store = store.event_store
      def entry_index = store.entry_store

      # Convenience
      def mentry_for(key)
        manifest.resolver.resolve(key).entry
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
        )
      end
    end
  end
end
