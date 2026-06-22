module Textus
  class Store
    class Container
      Infrastructure = Data.define(:file_store, :schemas, :audit_log, :job_store, :geometry)
      Coordination   = Data.define(:manifest, :workflows, :gate, :compositor, :pipeline)

      def self.attribute_names
        @attribute_names ||= [:root] + Infrastructure.members + Coordination.members
      end

      def initialize(infra, coord)
        @infra = infra
        @coord = coord
      end

      attr_reader :infra, :coord

      def root
        @infra.geometry.root
      end

      Infrastructure.members.each do |name|
        define_method(name) { @infra.public_send(name) }
      end

      Coordination.members.each do |name|
        define_method(name) { @coord.public_send(name) }
      end

      def self.build_full(infra, coord_seed)
        temp = new(infra, coord_seed)
        compositor = Store::Compositor.new(temp)
        gate = Textus::Gate.new(temp)
        coord = Coordination.new(
          manifest: coord_seed.manifest,
          workflows: coord_seed.workflows,
          gate:,
          compositor:,
          pipeline: nil,
        )
        container = new(infra, coord)
        compositor.instance_variable_set(:@container, container)
        gate.instance_variable_set(:@container, container)
        pipeline = build_pipeline(container)
        coord_w_pipeline = Coordination.new(
          manifest: coord_seed.manifest,
          workflows: coord_seed.workflows,
          gate:,
          compositor:,
          pipeline: pipeline,
        )
        container.instance_variable_set(:@coord, coord_w_pipeline)
        container
      end

      def self.build_pipeline(container)
        registry = HandlerRegistry.new

        registry.register(Contracts::GetEntry, Handlers::GetEntry.new(
          compositor: container.compositor,
          freshness_evaluator: freshness_evaluator(container)))
        registry.register(Contracts::PutEntry, Handlers::PutEntry.new(compositor: container.compositor))
        registry.register(Contracts::ListKeys, Handlers::ListKeys.new(manifest: container.manifest))
        registry.register(Contracts::DeleteKey, Handlers::DeleteKey.new(compositor: container.compositor))
        registry.register(Contracts::MoveKey, Handlers::MoveKey.new(
          compositor: container.compositor, manifest: container.manifest))
        registry.register(Contracts::ProposeEntry, Handlers::ProposeEntry.new(compositor: container.compositor))
        registry.register(Contracts::AcceptProposal, Handlers::AcceptProposal.new(compositor: container.compositor))
        registry.register(Contracts::RejectProposal, Handlers::RejectProposal.new(compositor: container.compositor))
        registry.register(Contracts::EnqueueJob, Handlers::EnqueueJob.new(job_store: container.job_store))
        registry.register(Contracts::AuditEntries, Handlers::AuditEntries.new(
          manifest: container.manifest, audit_log: container.audit_log))
        registry.register(Contracts::PulseEntries, Handlers::PulseEntries.new(
          container: container, manifest: container.manifest,
          audit_log: container.audit_log, file_store: container.file_store))
        registry.register(Contracts::BlameEntry, Handlers::BlameEntry.new(
          manifest: container.manifest, audit_log: container.audit_log))
        registry.register(Contracts::WhereEntry, Handlers::WhereEntry.new(manifest: container.manifest))
        registry.register(Contracts::UidEntry, Handlers::UidEntry.new(compositor: container.compositor))
        registry.register(Contracts::DepsEntry, Handlers::DepsEntry.new(manifest: container.manifest))
        registry.register(Contracts::RdepsEntry, Handlers::RdepsEntry.new(manifest: container.manifest))
        registry.register(Contracts::BootStore, Handlers::BootStore.new(container: container))
        registry.register(Contracts::DoctorStore, Handlers::DoctorStore.new(container: container))
        registry.register(Contracts::PublishedEntries, Handlers::PublishedEntries.new(manifest: container.manifest))
        registry.register(Contracts::RuleExplain, Handlers::RuleExplain.new(manifest: container.manifest))
        registry.register(Contracts::RuleList, Handlers::RuleList.new(manifest: container.manifest))
        registry.register(Contracts::SchemaEnvelope, Handlers::SchemaEnvelope.new(
          manifest: container.manifest, schemas: container.schemas))
        registry.register(Contracts::DrainStore, Handlers::DrainStore.new(
          container: container, job_store: container.job_store))
        registry.register(Contracts::IngestEntry, Handlers::IngestEntry.new(container: container))
        registry.register(Contracts::JobsAction, Handlers::JobsAction.new(job_store: container.job_store))
        registry.register(Contracts::RuleLint, Handlers::RuleLint.new(manifest: container.manifest))
        registry.register(Contracts::DataMv, Handlers::DataMv.new(compositor: container.compositor))
        registry.register(Contracts::KeyMvPrefix, Handlers::KeyMvPrefix.new(
          compositor: container.compositor, manifest: container.manifest))
        registry.register(Contracts::KeyDeletePrefix, Handlers::KeyDeletePrefix.new(
          compositor: container.compositor, manifest: container.manifest))

        Bus::Pipeline.new(
          registry: registry,
          middleware: [
            Bus::Middleware::Binder.new,
            Bus::Middleware::Auth.new(container.manifest),
            Bus::Middleware::Cascade.new(container),
          ],
        )
      end

      def self.freshness_evaluator(container)
        Textus::Core::Freshness::Evaluator.new(
          manifest: container.manifest,
          file_stat: Textus::Port::Storage::FileStat.new,
          clock: Textus::Port::Clock.new,
        )
      end
    end
  end
end
