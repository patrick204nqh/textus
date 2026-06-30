module Textus
  module Dispatch
    class Assembler
      COMPUTED_KEYS = %i[
        container manifest audit_log file_store job_store schemas
        link_edge_store layout freshness_evaluator orchestration
        reader event_bus workflows pipeline
      ].to_set.freeze

      # One row per verb: [ContractClass, HandlerClass, { kwarg_name: :computed_key }]
      HANDLER_MANIFEST = [
        [Contracts::GetEntry,        Handlers::Read::GetEntry,
         { file_store: :file_store, manifest: :manifest, layout: :layout,
           freshness_evaluator: :freshness_evaluator }],
        [Contracts::PutEntry,        Handlers::Write::PutEntry,
         { file_store: :file_store, manifest: :manifest, schemas: :schemas,
           audit_log: :audit_log, layout: :layout, event_bus: :event_bus }],
        [Contracts::ListKeys,        Handlers::Read::ListKeys, { manifest: :manifest, job_store: :job_store }],
        [Contracts::DeleteKey,       Handlers::Write::DeleteKey,
         { file_store: :file_store, manifest: :manifest, schemas: :schemas,
           audit_log: :audit_log, layout: :layout, event_bus: :event_bus }],
        [Contracts::MoveKey,         Handlers::Write::MoveKey,
         { file_store: :file_store, manifest: :manifest, schemas: :schemas,
           audit_log: :audit_log, layout: :layout }],
        [Contracts::ProposeEntry,    Handlers::Write::ProposeEntry,
         { file_store: :file_store, manifest: :manifest, schemas: :schemas,
           audit_log: :audit_log, layout: :layout, event_bus: :event_bus }],
        [Contracts::AcceptProposal,  Handlers::Write::AcceptProposal,
         { file_store: :file_store, manifest: :manifest, schemas: :schemas,
           audit_log: :audit_log, layout: :layout, event_bus: :event_bus }],
        [Contracts::RejectProposal,  Handlers::Write::RejectProposal,
         { file_store: :file_store, manifest: :manifest, schemas: :schemas,
           audit_log: :audit_log, layout: :layout, event_bus: :event_bus }],
        [Contracts::EnqueueJob,      Handlers::Write::EnqueueJob,      { job_store: :job_store }],
        [Contracts::WhereEntry,      Handlers::Read::WhereEntry,       { manifest: :manifest }],
        [Contracts::UidEntry,        Handlers::Read::UidEntry,
         { file_store: :file_store, manifest: :manifest, layout: :layout }],
        [Contracts::DepsEntry,       Handlers::Read::DepsEntry, { manifest: :manifest }],
        [Contracts::RdepsEntry,      Handlers::Read::RdepsEntry,
         { manifest: :manifest, link_edge_store: :link_edge_store }],
        [Contracts::BootStore,       Handlers::Maintenance::BootStore,
         { manifest: :manifest, file_store: :file_store, schemas: :schemas,
           audit_log: :audit_log, layout: :layout, pipeline: :pipeline }],
        [Contracts::DoctorStore,     Handlers::Maintenance::DoctorStore,
         { manifest: :manifest, file_store: :file_store, layout: :layout,
           pipeline: :pipeline, audit_log: :audit_log, schemas: :schemas }],
        [Contracts::PublishedEntries, Handlers::Maintenance::PublishedEntries, { manifest: :manifest }],
        [Contracts::RuleExplain,     Handlers::Maintenance::RuleExplain,     { manifest: :manifest }],
        [Contracts::RuleList,        Handlers::Maintenance::RuleList,        { manifest: :manifest }],
        [Contracts::SchemaEnvelope,  Handlers::Maintenance::SchemaEnvelope,
         { manifest: :manifest, schemas: :schemas }],
        [Contracts::DrainStore,      Handlers::Maintenance::DrainStore,
         { manifest: :manifest, file_store: :file_store, schemas: :schemas,
           audit_log: :audit_log, job_store: :job_store, layout: :layout,
           workflows: :workflows }],
        [Contracts::IngestEntry,     Handlers::Maintenance::IngestEntry,
         { manifest: :manifest, file_store: :file_store, schemas: :schemas,
           audit_log: :audit_log, job_store: :job_store, layout: :layout }],
        [Contracts::JobsAction,      Handlers::Maintenance::JobsAction,      { job_store: :job_store }],
        [Contracts::RuleLint,        Handlers::Maintenance::RuleLint,        { manifest: :manifest }],
        [Contracts::DataMv,          Handlers::Write::DataMv,                { manifest: :manifest, layout: :layout }],
        [Contracts::AuditEntries,    Handlers::Read::AuditEntries,
         { manifest: :manifest, audit_log: :audit_log }],
        [Contracts::PulseEntries,    Handlers::Read::PulseEntries,
         { manifest: :manifest, audit_log: :audit_log,
           file_store: :file_store, job_store: :job_store, orchestration: :orchestration }],
        [Contracts::BlameEntry,      Handlers::Read::BlameEntry,
         { manifest: :manifest, orchestration: :orchestration }],
        [Contracts::KeyMvPrefix,     Handlers::Write::KeyMvPrefix,     { orchestration: :orchestration }],
        [Contracts::KeyDeletePrefix, Handlers::Write::KeyDeletePrefix, { orchestration: :orchestration }],
      ].freeze

      MIDDLEWARE_MANIFEST = [
        ->(_c) { Middleware::Binder.new },
        ->(_c) { Middleware::Auth.new },
        ->(c)  { Middleware::AuditIndex.new(job_store: c.job_store, audit_log: c.audit_log) },
        ->(_c) { Middleware::Cascade.new },
      ].freeze

      def self.build_pipeline(container:)
        fe   = freshness_evaluator(container)
        orch = Store::Container.orchestration_for(container)
        rdr  = Textus::Store::Entry::Reader.new(
          file_store: container.file_store, manifest: container.manifest,
          layout: container.layout
        )

        computed = {
          container:,
          manifest: container.manifest,
          audit_log: container.audit_log,
          file_store: container.file_store,
          job_store: container.job_store,
          layout: container.layout,
          schemas: container.schemas,
          link_edge_store: container.link_edge_store,
          freshness_evaluator: fe,
          orchestration: orch,
          reader: rdr,
          event_bus: Textus::Event::Bus.new,
          workflows: container.workflows,
          pipeline: container.pipeline,
        }

        registry = HandlerRegistry.new
        HANDLER_MANIFEST.each do |contract_class, handler_class, dep_map|
          deps = dep_map.transform_values { |key| computed.fetch(key) }
          if handler_class.instance_of?(Module)
            dep_struct = Data.define(*dep_map.keys).new(**deps)
            registry.register(contract_class, ->(command, call) { handler_class.call(command, call, dep_struct) })
          else
            registry.register(contract_class, handler_class.new(**deps))
          end
        end

        middleware = MIDDLEWARE_MANIFEST.map { |factory| factory.call(container) }
        Pipeline.new(registry:, container:, middleware:)
      end

      def self.freshness_evaluator(container)
        Store::Freshness::TtlEvaluator.new(
          manifest: container.manifest,
          file_stat: Textus::Port::Storage::FileStat.new,
          clock: Textus::Port::Clock.new,
        )
      end
    end
  end
end
