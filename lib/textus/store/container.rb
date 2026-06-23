module Textus
  class Store
    class Container
      Infrastructure = Data.define(:file_store, :schemas, :audit_log, :job_store, :geometry)
      Coordination   = Data.define(:manifest, :workflows, :pipeline)

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
        coord = Coordination.new(
          manifest: coord_seed.manifest,
          workflows: coord_seed.workflows,
          pipeline: nil,
        )
        container = new(infra, coord)
        pipeline = build_pipeline(container)
        coord_with_pipeline = Coordination.new(
          manifest: coord_seed.manifest,
          workflows: coord_seed.workflows,
          pipeline: pipeline,
        )
        container.instance_variable_set(:@coord, coord_with_pipeline)
        container
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def self.build_pipeline(container)
        registry = Dispatch::HandlerRegistry.new
        orchestration = Handlers::Orchestration.new(
          list_keys: Handlers::ListKeys.new(manifest: container.manifest),
          move_key: Handlers::MoveKey.new(container: container, manifest: container.manifest),
          delete_key: Handlers::DeleteKey.new(container: container),
          audit_entries: Handlers::AuditEntries.new(manifest: container.manifest, audit_log: container.audit_log),
        )

        registry.register(Dispatch::Contracts::GetEntry, Handlers::GetEntry.new(
                                                           container: container,
                                                           freshness_evaluator: freshness_evaluator(container),
                                                         ))
        registry.register(Dispatch::Contracts::PutEntry, Handlers::PutEntry.new(container: container))
        registry.register(Dispatch::Contracts::ListKeys, Handlers::ListKeys.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::DeleteKey, Handlers::DeleteKey.new(container: container))
        registry.register(Dispatch::Contracts::MoveKey, Handlers::MoveKey.new(
                                                          container: container, manifest: container.manifest,
                                                        ))
        registry.register(Dispatch::Contracts::ProposeEntry, Handlers::ProposeEntry.new(container: container))
        registry.register(Dispatch::Contracts::AcceptProposal, Handlers::AcceptProposal.new(container: container))
        registry.register(Dispatch::Contracts::RejectProposal, Handlers::RejectProposal.new(container: container))
        registry.register(Dispatch::Contracts::EnqueueJob, Handlers::EnqueueJob.new(job_store: container.job_store))
        registry.register(Dispatch::Contracts::AuditEntries, Handlers::AuditEntries.new(
                                                               manifest: container.manifest, audit_log: container.audit_log,
                                                             ))
        registry.register(Dispatch::Contracts::PulseEntries, Handlers::PulseEntries.new(
                                                               manifest: container.manifest,
                                                               audit_log: container.audit_log,
                                                               file_store: container.file_store,
                                                               orchestration: orchestration,
                                                             ))
        registry.register(Dispatch::Contracts::BlameEntry, Handlers::BlameEntry.new(
                                                             manifest: container.manifest,
                                                             orchestration: orchestration,
                                                           ))
        registry.register(Dispatch::Contracts::WhereEntry, Handlers::WhereEntry.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::UidEntry, Handlers::UidEntry.new(container: container))
        registry.register(Dispatch::Contracts::DepsEntry, Handlers::DepsEntry.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::RdepsEntry, Handlers::RdepsEntry.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::BootStore, Handlers::BootStore.new(container: container))
        registry.register(Dispatch::Contracts::DoctorStore, Handlers::DoctorStore.new(container: container))
        registry.register(Dispatch::Contracts::PublishedEntries, Handlers::PublishedEntries.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::RuleExplain, Handlers::RuleExplain.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::RuleList, Handlers::RuleList.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::SchemaEnvelope, Handlers::SchemaEnvelope.new(
                                                                 manifest: container.manifest, schemas: container.schemas,
                                                               ))
        registry.register(Dispatch::Contracts::DrainStore, Handlers::DrainStore.new(
                                                             container: container, job_store: container.job_store,
                                                           ))
        registry.register(Dispatch::Contracts::IngestEntry, Handlers::IngestEntry.new(container: container))
        registry.register(Dispatch::Contracts::JobsAction, Handlers::JobsAction.new(job_store: container.job_store))
        registry.register(Dispatch::Contracts::RuleLint, Handlers::RuleLint.new(manifest: container.manifest))
        registry.register(Dispatch::Contracts::DataMv, Handlers::DataMv.new(container: container))
        registry.register(Dispatch::Contracts::KeyMvPrefix, Handlers::KeyMvPrefix.new(
                                                              orchestration: orchestration,
                                                            ))
        registry.register(Dispatch::Contracts::KeyDeletePrefix, Handlers::KeyDeletePrefix.new(
                                                                  orchestration: orchestration,
                                                                ))

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
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def self.freshness_evaluator(container)
        Store::Freshness::Evaluator.new(
          manifest: container.manifest,
          file_stat: Textus::Port::Storage::FileStat.new,
          clock: Textus::Port::Clock.new,
        )
      end
    end
  end
end
