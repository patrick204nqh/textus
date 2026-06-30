module Textus
  module Dispatch
    class Assembler
      COMPUTED_KEYS = %i[
        container manifest audit_log file_store job_store schemas link_edge_store fe orch
      ].to_set.freeze

      # One row per verb: [ContractClass, HandlerClass, { kwarg_name: :computed_key }]
      # Computed key legend:
      #   :container       → the Container itself
      #   :manifest        → container.manifest
      #   :audit_log       → container.audit_log
      #   :file_store      → container.file_store
      #   :job_store       → container.job_store
      #   :schemas         → container.schemas
      #   :link_edge_store → container.link_edge_store
      #   :fe              → TtlEvaluator (built once)
      #   :orch            → Orchestration (built once, shared by 4 handlers)
      HANDLER_MANIFEST = [
        [Contracts::GetEntry,        Handlers::Read::GetEntry,
         { container: :container, freshness_evaluator: :fe }],
        [Contracts::PutEntry,        Handlers::Write::PutEntry,        { container: :container }],
        [Contracts::ListKeys,        Handlers::Read::ListKeys,         { manifest: :manifest, job_store: :job_store }],
        [Contracts::DeleteKey,       Handlers::Write::DeleteKey,       { container: :container }],
        [Contracts::MoveKey,         Handlers::Write::MoveKey,         { container: :container, manifest: :manifest }],
        [Contracts::ProposeEntry,    Handlers::Write::ProposeEntry,    { container: :container }],
        [Contracts::AcceptProposal,  Handlers::Write::AcceptProposal,  { container: :container }],
        [Contracts::RejectProposal,  Handlers::Write::RejectProposal,  { container: :container }],
        [Contracts::EnqueueJob,      Handlers::Write::EnqueueJob,      { job_store: :job_store }],
        [Contracts::WhereEntry,      Handlers::Read::WhereEntry,       { manifest: :manifest }],
        [Contracts::UidEntry,        Handlers::Read::UidEntry,         { container: :container }],
        [Contracts::DepsEntry,       Handlers::Read::DepsEntry,        { manifest: :manifest }],
        [Contracts::RdepsEntry,      Handlers::Read::RdepsEntry,
         { manifest: :manifest, link_edge_store: :link_edge_store }],
        [Contracts::BootStore,       Handlers::Maintenance::BootStore,       { container: :container }],
        [Contracts::DoctorStore,     Handlers::Maintenance::DoctorStore,     { container: :container }],
        [Contracts::PublishedEntries, Handlers::Maintenance::PublishedEntries, { manifest: :manifest }],
        [Contracts::RuleExplain,     Handlers::Maintenance::RuleExplain,     { manifest: :manifest }],
        [Contracts::RuleList,        Handlers::Maintenance::RuleList,        { manifest: :manifest }],
        [Contracts::SchemaEnvelope,  Handlers::Maintenance::SchemaEnvelope,
         { manifest: :manifest, schemas: :schemas }],
        [Contracts::DrainStore,      Handlers::Maintenance::DrainStore,
         { container: :container, job_store: :job_store }],
        [Contracts::IngestEntry,     Handlers::Maintenance::IngestEntry,     { container: :container }],
        [Contracts::JobsAction,      Handlers::Maintenance::JobsAction,      { job_store: :job_store }],
        [Contracts::RuleLint,        Handlers::Maintenance::RuleLint,        { manifest: :manifest }],
        [Contracts::DataMv,          Handlers::Write::DataMv,                { container: :container }],
        [Contracts::AuditEntries,    Handlers::Read::AuditEntries,
         { manifest: :manifest, audit_log: :audit_log }],
        [Contracts::PulseEntries,    Handlers::Read::PulseEntries,
         { manifest: :manifest, audit_log: :audit_log,
           file_store: :file_store, job_store: :job_store, orchestration: :orch }],
        [Contracts::BlameEntry,      Handlers::Read::BlameEntry,
         { manifest: :manifest, orchestration: :orch }],
        [Contracts::KeyMvPrefix,     Handlers::Write::KeyMvPrefix,     { orchestration: :orch }],
        [Contracts::KeyDeletePrefix, Handlers::Write::KeyDeletePrefix, { orchestration: :orch }],
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

        computed = {
          container:,
          manifest: container.manifest,
          audit_log: container.audit_log,
          file_store: container.file_store,
          job_store: container.job_store,
          schemas: container.schemas,
          link_edge_store: container.link_edge_store,
          fe:,
          orch:,
        }

        registry = HandlerRegistry.new
        HANDLER_MANIFEST.each do |contract_class, handler_class, dep_map|
          deps = dep_map.transform_values { |key| computed.fetch(key) }
          registry.register(contract_class, handler_class.new(**deps))
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
