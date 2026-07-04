module Textus
  module Workflow
    Context = Data.define(:key, :entry, :config, :lane, :container, :call) do
      def manifest    = container.manifest
      def layout      = container.layout
      def schemas     = container.schemas
      def file_system = container.store.file_system
      def read(key)   = container.store.entry_store.read(key, manifest: container.manifest, layout: container.layout)
      def repo_root   = File.dirname(container.root)
      def store_root  = container.root
    end
  end
end
