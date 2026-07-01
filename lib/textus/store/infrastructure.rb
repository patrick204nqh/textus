module Textus
  class Store
    Infrastructure = Data.define(
      :manifest,          # Textus::Manifest
      :file_store,        # Port::Storage::FileStore
      :schemas,           # Schema::Registry
      :audit_log,         # Port::AuditLog
      :job_store,         # Port::Store
      :layout,            # Store::Layout
      :link_edge_store,   # Links::LinkEdgeStore
      :workflows,         # Workflow::Registry
      :event_bus,         # Event::Bus (session-scoped)
      :freshness_evaluator, # Store::Freshness::TtlEvaluator
      :trace_buffer, # Store::TraceBuffer (ring buffer for dispatch traces)
      :pipeline, # Dispatch::Pipeline (nil until wired)
    )
  end
end
