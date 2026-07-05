module Textus
  module Protocol
    class StoreEngine
      def initialize(file_system:, manifest:, layout:, store:, workflow_registry: nil)
        @file_system = file_system
        @manifest = manifest
        @layout = layout
        @store = store
        @workflow_registry = workflow_registry
      end

      def read(key:)
        result = resolve(key:)
        path = result.path
        return nil unless path && @file_system.exists?(path)

        raw = @file_system.read(path)
        parsed = Format.for(result.entry.format).parse(raw, path:)
        Envelope.build(key:, mentry: result.entry, path:,
                       meta: parsed["_meta"] || {},
                       body: parsed["body"] || "",
                       content: parsed["content"],
                       etag: Value::Etag.for_file(path))
      end

      def exists?(key:)
        path = resolve(key:).path
        path && @file_system.exists?(path)
      end

      def list(prefix: nil, lane: nil, q: nil, schema: nil)
        if @store.entry_index && (q || schema)
          rows = @store.entry_index.search(query: q, schema:, lane:, prefix:)
          (rows || []).map { |r| { "key" => r["key"], "lane" => r["lane"] } }
        else
          rows = @manifest.resolver.enumerate(prefix:)
          rows = rows.select { |r| r[:manifest_entry].lane == lane } if lane
          rows.map { |r| { "key" => r[:key], "lane" => r[:manifest_entry].lane } }
        end
      end

      def resolve(key:)   = @manifest.resolver.resolve(key)
      def mentry_for(key:)= resolve(key:).entry
      attr_reader :manifest, :layout

      def put(key:, meta:, body:, content:, call:, if_etag: nil)
        result = resolve(key:)
        payload = Value::Payload.new(meta: meta || {}, body:, content:)
        PutPipeline.call(key, mentry: result.entry, path: result.path, payload:, call:,
                              file_system: @file_system, manifest: @manifest, store: @store,
                              layout: @layout, if_etag:,
                              workflow_registry: @workflow_registry)
      end

      def delete(key:, call:, if_etag: nil)
        DeletePipeline.call(key, call:,
                                 file_system: @file_system, manifest: @manifest, store: @store,
                                 layout: @layout, if_etag:)
      end

      def move(from_key:, to_key:, call:, if_etag: nil, dry_run: false)
        MovePipeline.call(from_key:, to_key:, call:, if_etag:, dry_run:,
                          file_system: @file_system, manifest: @manifest, store: @store,
                          layout: @layout, reader: self)
      end

      def audit_log     = @store.audit_log
      def link_store    = @store.link_store
      def cursor_store  = @store.cursor_store
      def workflow_queue = @store.workflow_queue
      def entry_index   = @store.entry_index
      def file_store    = @store.file_store
    end
  end
end
