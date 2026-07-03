module Textus
  module Workflow
    Context = Data.define(:key, :entry, :config, :lane, :container, :call) do
      def manifest   = container.manifest
      def repo_root  = File.dirname(container.root)
      def store_root = container.root

      def scoped
        ScopedContext.new(container:)
      end
    end

    class ScopedContext
      def initialize(container:)
        @container = container
      end

      def get(key)
        @container.reader.read(key)
      end

      def list(prefix: nil)
        @container.entry_index.search(query: nil, schema: nil, lane: nil, prefix:)
      end

      def search(query:, schema: nil, lane: nil, prefix: nil)
        @container.entry_index.search(query:, schema:, lane:, prefix:)
      end

      def config
        @container.manifest.data
      end
    end
  end
end
