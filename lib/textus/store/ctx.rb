module Textus
  class Store
    Ctx = Data.define(
      :manifest,        # Textus::Manifest
      :file_store,      # Port::Storage::FileStore
      :schemas,         # Schema::Registry
      :audit_log,       # Port::AuditLog
      :job_store,       # Port::Store
      :layout,          # Store::Layout
      :link_edge_store, # Links::LinkEdgeStore
      :workflows,       # Workflow::Registry
      :event_bus,       # Event::Bus (session-scoped)
      :pipeline,        # Dispatch::Pipeline (nil until Boot.wire finishes)
    )
  end
end
