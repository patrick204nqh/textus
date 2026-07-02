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
      :workflows,         # Array<Workflow::DSL::Definition>
      :root,              # String — store root path
      :reader,            # Store::Entry::Reader
      :writer,            # Store::Entry::Writer
      :event_bus,         # Event::Bus (session-scoped)
      :freshness_evaluator, # Store::Freshness::TtlEvaluator
      :trace_buffer, # Store::TraceBuffer (ring buffer for dispatch traces)
      :pipeline, # Dispatch::Pipeline (nil until wired)
    ) do
      def self.build(**kwargs)
        members = self.members
        defaults = members - kwargs.keys
        new(**kwargs, **defaults.to_h { |m| [m, nil] })
      end
    end
  end
end
