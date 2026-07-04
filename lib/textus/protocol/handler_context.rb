module Textus
  module Protocol
    class HandlerContext
      def initialize(container)
        @container = container
      end

      # Reading
      def read(key)
        @container.reader.read(key)
      end

      def list(prefix: nil, lane: nil, q: nil, schema: nil)
        @container.entry_index.search(query: q, schema:, lane:, prefix:)
      end

      def exists?(key)
        @container.reader.exists?(key)
      end

      def resolve(key)
        @container.manifest.resolver.resolve(key)
      end

      # Writing
      def write(key, mentry:, payload:, if_etag: nil, call: nil)
        @container.writer.put(key, mentry:, payload:, if_etag:, call:)
      end

      def delete(key, if_etag: nil, mentry: nil, call: nil)
        @container.writer.delete(key, if_etag:, mentry:, call:)
      end

      def move(from_key:, to_key:, new_mentry:, call: nil)
        @container.writer.move(from_key:, to_key:, new_mentry:, call:)
      end

      # Query
      def manifest  = @container.manifest
      def layout    = @container.layout
      def audit     = @container.audit_log
      def links     = @container.link_graph
      def schemas   = @container.schemas
      def file_system = @container.file_system
      def event_store = @container.event_store
      def workflows   = @container.workflows
      def entry_index = @container.entry_index
      def container   = @container

      # Convenience
      def mentry_for(key)
        manifest.resolver.resolve(key).entry
      end

      def payload(meta: nil, body: nil, content: nil)
        Textus::Value::Payload.new(meta: meta || {}, body:, content:)
      end
    end
  end
end