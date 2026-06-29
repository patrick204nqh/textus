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

      def self.build_full(infra, coord_seed)
        coord = Coordination.new(
          manifest: coord_seed.manifest,
          workflows: coord_seed.workflows,
          pipeline: nil,
        )
        container = new(infra, coord)
        # Use the HandlerFactoryRegistry + Pipeline::Adapter (Design B).
        # The registry is populated with factories via register_builder_handlers
        # and the Adapter builds a Dispatch::Pipeline from that registry.
        factory_registry = Dispatch::Pipeline::HandlerFactoryRegistry.new
        register_builder_handlers(factory_registry)

        adapter = Dispatch::Pipeline::Adapter.new(
          container: container,
          factory_registry: factory_registry,
          middleware: [
            Dispatch::Middleware::Binder.new,
            Dispatch::Middleware::Auth.new,
            Dispatch::Middleware::Cascade.new,
          ],
        )

        pipeline = adapter.pipeline

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
        writer_factory = create_writer_factory(container)
        container.instance_variable_set(:@writer, writer_factory)
        container
      end

      def self.register_builder_handlers(builder)
        manifest_handler = ->(handler_class) { ->(c) { handler_class.new(manifest: c.manifest) } }
        container_handler = ->(handler_class) { ->(c) { handler_class.new(container: c) } }
        job_store_handler = ->(handler_class) { ->(c) { handler_class.new(job_store: c.job_store) } }

        # Core registrations that don't require orchestration
        builder.register(Dispatch::Contracts::GetEntry, lambda { |c|
          Handlers::GetEntry.new(container: c, freshness_evaluator: freshness_evaluator(c))
        })

        register_basic_handlers(builder, manifest_handler, container_handler, job_store_handler)

        register_orchestration_handlers(builder)
      end

      def self.orchestration_for(container)
        Handlers::Orchestration.new(
          list_keys: Handlers::ListKeys.new(manifest: container.manifest),
          move_key: Handlers::MoveKey.new(container: container, manifest: container.manifest),
          delete_key: Handlers::DeleteKey.new(container: container),
          audit_entries: Handlers::AuditEntries.new(manifest: container.manifest, audit_log: container.audit_log),
        )
      end

      def self.register_basic_handlers(builder, manifest_hnd, container_hnd, job_store_hnd)
        builder.register(Dispatch::Contracts::PutEntry, container_hnd.call(Handlers::PutEntry))
        builder.register(Dispatch::Contracts::ListKeys, manifest_hnd.call(Handlers::ListKeys))
        builder.register(Dispatch::Contracts::DeleteKey, container_hnd.call(Handlers::DeleteKey))
        builder.register(Dispatch::Contracts::MoveKey, ->(c) { Handlers::MoveKey.new(container: c, manifest: c.manifest) })
        builder.register(Dispatch::Contracts::ProposeEntry, container_hnd.call(Handlers::ProposeEntry))
        builder.register(Dispatch::Contracts::AcceptProposal, container_hnd.call(Handlers::AcceptProposal))
        builder.register(Dispatch::Contracts::RejectProposal, container_hnd.call(Handlers::RejectProposal))
        builder.register(Dispatch::Contracts::EnqueueJob, job_store_hnd.call(Handlers::EnqueueJob))

        builder.register(Dispatch::Contracts::WhereEntry, manifest_hnd.call(Handlers::WhereEntry))
        builder.register(Dispatch::Contracts::UidEntry, container_hnd.call(Handlers::UidEntry))
        builder.register(Dispatch::Contracts::DepsEntry, manifest_hnd.call(Handlers::DepsEntry))
        builder.register(Dispatch::Contracts::RdepsEntry, manifest_hnd.call(Handlers::RdepsEntry))
        builder.register(Dispatch::Contracts::BootStore, container_hnd.call(Handlers::BootStore))
        builder.register(Dispatch::Contracts::DoctorStore, container_hnd.call(Handlers::DoctorStore))
        builder.register(Dispatch::Contracts::PublishedEntries, manifest_hnd.call(Handlers::PublishedEntries))
        builder.register(Dispatch::Contracts::RuleExplain, manifest_hnd.call(Handlers::RuleExplain))
        builder.register(Dispatch::Contracts::RuleList, manifest_hnd.call(Handlers::RuleList))
        builder.register(Dispatch::Contracts::SchemaEnvelope, lambda { |c|
          Handlers::SchemaEnvelope.new(manifest: c.manifest, schemas: c.schemas)
        })
        builder.register(Dispatch::Contracts::DrainStore, ->(c) { Handlers::DrainStore.new(container: c, job_store: c.job_store) })
        builder.register(Dispatch::Contracts::IngestEntry, container_hnd.call(Handlers::IngestEntry))
        builder.register(Dispatch::Contracts::JobsAction, job_store_hnd.call(Handlers::JobsAction))
        builder.register(Dispatch::Contracts::RuleLint, manifest_hnd.call(Handlers::RuleLint))
        builder.register(Dispatch::Contracts::DataMv, container_hnd.call(Handlers::DataMv))
      end

      def self.register_orchestration_handlers(builder)
        # AuditEntries needs both manifest and audit_log
        builder.register(Dispatch::Contracts::AuditEntries, lambda { |c|
          Handlers::AuditEntries.new(manifest: c.manifest, audit_log: c.audit_log)
        })

        builder.register(Dispatch::Contracts::PulseEntries, lambda { |c|
          Handlers::PulseEntries.new(
            manifest: c.manifest,
            audit_log: c.audit_log,
            file_store: c.file_store,
            orchestration: orchestration_for(c),
          )
        })

        builder.register(Dispatch::Contracts::BlameEntry, lambda { |c|
          Handlers::BlameEntry.new(manifest: c.manifest, orchestration: orchestration_for(c))
        })

        builder.register(Dispatch::Contracts::KeyMvPrefix, lambda { |c|
          Handlers::KeyMvPrefix.new(orchestration: orchestration_for(c))
        })

        builder.register(Dispatch::Contracts::KeyDeletePrefix, lambda { |c|
          Handlers::KeyDeletePrefix.new(orchestration: orchestration_for(c))
        })
      end

      def self.create_writer_factory(container)
        lambda do |call|
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
      end

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
