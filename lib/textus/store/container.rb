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

      def link_edge_store
        @link_edge_store ||= Textus::Links::LinkEdgeStore.new
      end

      def read_family(prefix, include_keyless: false)
        manifest.resolver
                .enumerate(prefix: prefix, include_keyless: include_keyless)
                .filter_map { |row| reader.read(row[:key]) }
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
        list_deps = Data.define(:manifest, :job_store).new(
          manifest: container.manifest, job_store: container.job_store,
        )
        audit_deps = Data.define(:manifest, :audit_log).new(
          manifest: container.manifest, audit_log: container.audit_log,
        )
        move_deps = Data.define(:file_store, :manifest, :schemas, :audit_log, :layout).new(
          file_store: container.file_store, manifest: container.manifest,
          schemas: container.schemas, audit_log: container.audit_log,
          layout: container.layout
        )
        delete_deps = Data.define(:file_store, :manifest, :schemas, :audit_log, :layout).new(
          file_store: container.file_store, manifest: container.manifest,
          schemas: container.schemas, audit_log: container.audit_log,
          layout: container.layout
        )
        Orchestration.new(
          list_keys: ->(command, call) { Handlers::Read::ListKeys.call(command, call, list_deps) },
          move_key: ->(command, call) { Handlers::Write::MoveKey.call(command, call, move_deps) },
          delete_key: ->(command, call) { Handlers::Write::DeleteKey.call(command, call, delete_deps) },
          audit_entries: ->(command, call) { Handlers::Read::AuditEntries.call(command, call, audit_deps) },
        )
      end

      def self.build_pipeline(container)
        Dispatch::Assembler.build_pipeline(container:)
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
    end
  end
end
