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

      # Minor incremental injection points: allow the container to expose
      # a pre-built pipeline, reader, and writer. We keep existing
      # build_full behaviour but prefer these accessors when present so
      # tests can swap a single instance.
      attr_reader :pipeline, :reader, :writer

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def self.build_full(infra, coord_seed)
        coord = Coordination.new(
          manifest: coord_seed.manifest,
          workflows: coord_seed.workflows,
          pipeline: nil,
        )
        container = new(infra, coord)
        # Build pipeline via the Builder to keep composition local to the
        # Dispatch::Pipeline module. This concentrates handler wiring in a
        # smaller, test-friendly place and keeps the Pipeline interface
        # deep (small public surface, complex implementation hidden).
        builder = Dispatch::Pipeline::Builder.new(container)
        # Register handlers via factories so we preserve the previous
        # construction semantics while moving composition into the
        # builder. Create a few small local factory helpers to reduce
        # repetition for common constructor shapes.
        manifest_handler = ->(handler_class) { ->(c) { handler_class.new(manifest: c.manifest) } }
        container_handler = ->(handler_class) { ->(c) { handler_class.new(container: c) } }
        job_store_handler = ->(handler_class) { ->(c) { handler_class.new(job_store: c.job_store) } }

        builder.register(Dispatch::Contracts::GetEntry, lambda { |c|
          Handlers::GetEntry.new(container: c, freshness_evaluator: freshness_evaluator(c))
        })
        builder.register(Dispatch::Contracts::PutEntry, container_handler.call(Handlers::PutEntry))
        builder.register(Dispatch::Contracts::ListKeys, manifest_handler.call(Handlers::ListKeys))
        builder.register(Dispatch::Contracts::DeleteKey, container_handler.call(Handlers::DeleteKey))
        builder.register(Dispatch::Contracts::MoveKey, ->(c) { Handlers::MoveKey.new(container: c, manifest: c.manifest) })
        builder.register(Dispatch::Contracts::ProposeEntry, container_handler.call(Handlers::ProposeEntry))
        builder.register(Dispatch::Contracts::AcceptProposal, container_handler.call(Handlers::AcceptProposal))
        builder.register(Dispatch::Contracts::RejectProposal, container_handler.call(Handlers::RejectProposal))
        builder.register(Dispatch::Contracts::EnqueueJob, job_store_handler.call(Handlers::EnqueueJob))

        # Reuse an orchestration factory to avoid repeating the same
        # Handlers::Orchestration construction in multiple registrations.
        orchestration_factory = lambda do |c|
          Handlers::Orchestration.new(
            list_keys: Handlers::ListKeys.new(manifest: c.manifest),
            move_key: Handlers::MoveKey.new(container: c, manifest: c.manifest),
            delete_key: Handlers::DeleteKey.new(container: c),
            audit_entries: Handlers::AuditEntries.new(manifest: c.manifest, audit_log: c.audit_log),
          )
        end

        # AuditEntries needs both manifest and audit_log
        builder.register(Dispatch::Contracts::AuditEntries, lambda { |c|
          Handlers::AuditEntries.new(manifest: c.manifest, audit_log: c.audit_log)
        })
        builder.register(Dispatch::Contracts::PulseEntries, lambda { |c|
          Handlers::PulseEntries.new(
            manifest: c.manifest,
            audit_log: c.audit_log,
            file_store: c.file_store,
            orchestration: orchestration_factory.call(c),
          )
        })
        builder.register(Dispatch::Contracts::BlameEntry, lambda { |c|
          Handlers::BlameEntry.new(manifest: c.manifest, orchestration: orchestration_factory.call(c))
        })
        builder.register(Dispatch::Contracts::WhereEntry, manifest_handler.call(Handlers::WhereEntry))
        builder.register(Dispatch::Contracts::UidEntry, container_handler.call(Handlers::UidEntry))
        builder.register(Dispatch::Contracts::DepsEntry, manifest_handler.call(Handlers::DepsEntry))
        builder.register(Dispatch::Contracts::RdepsEntry, manifest_handler.call(Handlers::RdepsEntry))
        builder.register(Dispatch::Contracts::BootStore, container_handler.call(Handlers::BootStore))
        builder.register(Dispatch::Contracts::DoctorStore, container_handler.call(Handlers::DoctorStore))
        builder.register(Dispatch::Contracts::PublishedEntries, manifest_handler.call(Handlers::PublishedEntries))
        builder.register(Dispatch::Contracts::RuleExplain, manifest_handler.call(Handlers::RuleExplain))
        builder.register(Dispatch::Contracts::RuleList, manifest_handler.call(Handlers::RuleList))
        builder.register(Dispatch::Contracts::SchemaEnvelope, lambda { |c|
          Handlers::SchemaEnvelope.new(manifest: c.manifest, schemas: c.schemas)
        })
        builder.register(Dispatch::Contracts::DrainStore, ->(c) { Handlers::DrainStore.new(container: c, job_store: c.job_store) })
        builder.register(Dispatch::Contracts::IngestEntry, container_handler.call(Handlers::IngestEntry))
        builder.register(Dispatch::Contracts::JobsAction, job_store_handler.call(Handlers::JobsAction))
        builder.register(Dispatch::Contracts::RuleLint, manifest_handler.call(Handlers::RuleLint))
        builder.register(Dispatch::Contracts::DataMv, container_handler.call(Handlers::DataMv))
        builder.register(Dispatch::Contracts::KeyMvPrefix, lambda { |c|
          Handlers::KeyMvPrefix.new(orchestration: orchestration_factory.call(c))
        })
        builder.register(Dispatch::Contracts::KeyDeletePrefix, lambda { |c|
          Handlers::KeyDeletePrefix.new(orchestration: orchestration_factory.call(c))
        })

        pipeline = builder.build(middleware: [
                                   Dispatch::Middleware::Binder.new,
                                   Dispatch::Middleware::Auth.new,
                                   Dispatch::Middleware::Cascade.new,
                                 ])

        coord_with_pipeline = Coordination.new(
          manifest: coord_seed.manifest,
          workflows: coord_seed.workflows,
          pipeline: pipeline,
        )
        container.instance_variable_set(:@coord, coord_with_pipeline)
        # cache pipeline on the container instance so the attr_reader
        # we expose returns the constructed pipeline (keeps the
        # incremental injection behaviour consistent)
        container.instance_variable_set(:@pipeline, pipeline)
        # also create and cache a reader/writer for reuse; tests can
        # override container.instance_variable_set(:@reader, ...) if
        # they want to inject fakes.
        container.instance_variable_set(:@reader, Textus::Store::Envelope::Reader.from(container: container))
        # writer requires a call object; build a writer factory-like
        # accessor via a lambda stored on the container so callers can
        # request a writer for a call: container.writer_factory.call(call)
        # Build a writer factory that constructs Writer instances directly
        # (avoid calling Writer.from here which would prefer container.writer
        # and cause recursion). Use the cached reader so the writer shares
        # the same reader instance.
        writer_factory = lambda do |call|
          Textus::Store::Envelope::Writer.new(
            file_store: container.file_store,
            manifest: container.manifest,
            schemas: container.schemas,
            audit_log: container.audit_log,
            call: call,
            reader: container.reader,
            geometry: container.geometry,
          )
        end
        container.instance_variable_set(:@writer, writer_factory)
        container
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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
