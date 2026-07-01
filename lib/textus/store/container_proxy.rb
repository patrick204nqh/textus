module Textus
  class Store
    ContainerProxy = Data.define(
      :manifest, :file_store, :schemas, :audit_log, :job_store,
      :layout, :link_edge_store, :workflows, :pipeline, :root
    ) do
      def read_family(prefix, include_keyless: false)
        reader = Store::Entry::Reader.new(file_store:, manifest:, layout:)
        manifest.resolver
                .enumerate(prefix: prefix, include_keyless: include_keyless)
                .filter_map { |row| reader.read(row[:key]) }
      end
    end
  end
end
