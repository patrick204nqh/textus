module Textus
  class Store
    UseCaseContainer = Data.define(
      :manifest, :file_store, :schemas, :audit_log, :job_store,
      :layout, :link_edge_store, :workflows, :pipeline, :root
    ) do
      # Bulk read helper — intentionally bypasses use-case layer (no auth/audit).
      # Used by boot workflow, schema tools, and doctor checks where per-read
      # auth overhead would be excessive. Reader is read-only I/O, not a bypass
      # of write safeguards.
      def read_family(prefix, include_keyless: false)
        reader = Store::Entry::Reader.new(file_store:, manifest:, layout:)
        manifest.resolver
                .enumerate(prefix: prefix, include_keyless: include_keyless)
                .filter_map { |row| reader.read(row[:key]) }
      end
    end
  end
end
