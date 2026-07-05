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

      def put(key:, meta:, body:, content:, call:, if_etag: nil)
        result = resolve(key:)
        payload = Value::Payload.new(meta: meta || {}, body:, content:)
        deps = build_deps(reader: nil, call:)
        PutPipeline.call(key, mentry: result.entry, path: result.path, payload:, if_etag:, deps:)
      end

      def delete(key:, call:, if_etag: nil)
        deps = build_deps(reader: nil, call:)
        DeletePipeline.call(key, if_etag:, deps:)
      end

      def move(from_key:, to_key:, call:, if_etag: nil, dry_run: false)
        deps = build_deps(reader: self, call:)
        MovePipeline.call(from_key:, to_key:, if_etag:, dry_run:, deps:)
      end

      private

      def build_deps(reader:, call:)
        Pipeline::WriteDeps.new(
          file_system: @file_system, manifest: @manifest, store: @store,
          layout: @layout, workflow_registry: @workflow_registry, reader:, call:
        )
      end
    end
  end
end
