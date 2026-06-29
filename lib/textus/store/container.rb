module Textus
  class Store
    class Container
      Infrastructure = Data.define(:file_store, :schemas, :audit_log, :job_store, :layout)
      Coordination   = Data.define(:manifest, :workflows, :pipeline)

      def self.attribute_names
        @attribute_names ||= [:root] + Infrastructure.members + Coordination.members
      end

      def initialize(infra, coord)
        @infra = infra
        @coord = coord
      end

      attr_reader :infra, :coord, :pipeline, :reader, :writer

      def root
        @infra.layout.root
      end

      Infrastructure.members.each do |name|
        define_method(name) { @infra.public_send(name) }
      end

      Coordination.members.each do |name|
        define_method(name) { @coord.public_send(name) }
      end

      def wire!(pipeline:, reader:, writer:)
        @pipeline = pipeline
        @reader   = reader
        @writer   = writer
        @coord    = Coordination.new(
          manifest: @coord.manifest,
          workflows: @coord.workflows,
          pipeline: pipeline,
        )
        self
      end

      def self.build(infra, coord_seed)
        coord = Coordination.new(
          manifest: coord_seed.manifest,
          workflows: coord_seed.workflows,
          pipeline: nil,
        )
        container = new(infra, coord)
        pipeline = build_pipeline(container)
        reader   = Textus::Store::Entry::Reader.from(container: container)
        writer   = create_writer_factory(container)
        container.wire!(pipeline: pipeline, reader: reader, writer: writer)
      end

      def self.orchestration_for(container)
        Orchestration.new(
          list_keys: Handlers::Read::ListKeys.new(manifest: container.manifest),
          move_key: Handlers::Write::MoveKey.new(container: container, manifest: container.manifest),
          delete_key: Handlers::Write::DeleteKey.new(container: container),
          audit_entries: Handlers::Read::AuditEntries.new(manifest: container.manifest, audit_log: container.audit_log),
        )
      end

      def self.build_pipeline(container) # rubocop:disable Metrics/MethodLength
        registry = Dispatch::HandlerRegistry.new
        fe   = freshness_evaluator(container)
        orch = orchestration_for(container)

        registry.register(Dispatch::Contracts::GetEntry,
                          Handlers::Read::GetEntry.new(container: container, freshness_evaluator: fe))
        registry.register(Dispatch::Contracts::PutEntry,
                          Handlers::Write::PutEntry.new(container: container))
        registry.register(Dispatch::Contracts::ListKeys,
                          Handlers::Read::ListKeys.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::DeleteKey,
                          Handlers::Write::DeleteKey.new(container: container))
        registry.register(Dispatch::Contracts::MoveKey,
                          Handlers::Write::MoveKey.new(container: container, manifest: container.manifest))
        registry.register(Dispatch::Contracts::ProposeEntry,
                          Handlers::Write::ProposeEntry.new(container: container))
        registry.register(Dispatch::Contracts::AcceptProposal,
                          Handlers::Write::AcceptProposal.new(container: container))
        registry.register(Dispatch::Contracts::RejectProposal,
                          Handlers::Write::RejectProposal.new(container: container))
        registry.register(Dispatch::Contracts::EnqueueJob,
                          Handlers::Write::EnqueueJob.new(job_store: container.job_store))
        registry.register(Dispatch::Contracts::WhereEntry,
                          Handlers::Read::WhereEntry.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::UidEntry,
                          Handlers::Read::UidEntry.new(container: container))
        registry.register(Dispatch::Contracts::DepsEntry,
                          Handlers::Read::DepsEntry.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::RdepsEntry,
                          Handlers::Read::RdepsEntry.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::BootStore,
                          Handlers::Maintenance::BootStore.new(container: container))
        registry.register(Dispatch::Contracts::DoctorStore,
                          Handlers::Maintenance::DoctorStore.new(container: container))
        registry.register(Dispatch::Contracts::PublishedEntries,
                          Handlers::Maintenance::PublishedEntries.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::RuleExplain,
                          Handlers::Maintenance::RuleExplain.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::RuleList,
                          Handlers::Maintenance::RuleList.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::SchemaEnvelope,
                          Handlers::Maintenance::SchemaEnvelope.new(manifest: container.manifest, schemas: container.schemas))
        registry.register(Dispatch::Contracts::DrainStore,
                          Handlers::Maintenance::DrainStore.new(container: container, job_store: container.job_store))
        registry.register(Dispatch::Contracts::IngestEntry,
                          Handlers::Maintenance::IngestEntry.new(container: container))
        registry.register(Dispatch::Contracts::JobsAction,
                          Handlers::Maintenance::JobsAction.new(job_store: container.job_store))
        registry.register(Dispatch::Contracts::RuleLint,
                          Handlers::Maintenance::RuleLint.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::DataMv,
                          Handlers::Write::DataMv.new(container: container))
        registry.register(Dispatch::Contracts::AuditEntries,
                          Handlers::Read::AuditEntries.new(manifest: container.manifest, audit_log: container.audit_log))
        registry.register(Dispatch::Contracts::PulseEntries,
                          Handlers::Read::PulseEntries.new(
                            manifest: container.manifest,
                            audit_log: container.audit_log,
                            file_store: container.file_store,
                            orchestration: orch,
                          ))
        registry.register(Dispatch::Contracts::BlameEntry,
                          Handlers::Read::BlameEntry.new(manifest: container.manifest, orchestration: orch))
        registry.register(Dispatch::Contracts::KeyMvPrefix,
                          Handlers::Write::KeyMvPrefix.new(orchestration: orch))
        registry.register(Dispatch::Contracts::KeyDeletePrefix,
                          Handlers::Write::KeyDeletePrefix.new(orchestration: orch))

        Dispatch::Pipeline.new(
          registry: registry,
          container: container,
          middleware: [
            Dispatch::Middleware::Binder.new,
            Dispatch::Middleware::Auth.new,
            Dispatch::Middleware::Cascade.new,
          ],
        )
      end
      private_class_method :build_pipeline

      def self.create_writer_factory(container)
        lambda do |call|
          Textus::Store::Entry::Writer.new(
            file_store: container.file_store,
            manifest: container.manifest,
            schemas: container.schemas,
            audit_log: container.audit_log,
            call: call,
            reader: container.reader,
            layout: container.layout,
          )
        end
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
