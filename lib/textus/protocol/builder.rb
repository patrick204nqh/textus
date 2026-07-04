module Textus
  module Protocol
    class Builder
      def call(root)
        manifest    = Manifest.load(root)
        layout      = Protocol::Layout.new(root)
        database    = Infra::Database.new(layout:).setup!
        file_system = Infra::FileSystem.new
        schemas     = Protocol::Schema::Registry.new(layout.schemas_dir)

        store       = Infra::Store.new(database:, file_system:)
        workflows   = Workflow::Loader.load_all(root)
        workflows.push(Textus::Workflow::Instances::Materialize)

        ttl_evaluator = Protocol::Freshness::TtlEvaluator.new(
          manifest:,
          file_stat: file_system,
          clock: Infra::Clock.new,
        )

        container = Container.new(
          store:, layout:,
          manifest:, schemas:,
          workflows:,
          root:, ttl_evaluator:
        )

        gate = Protocol::Gate.new(
          manifest:,
          resolver: manifest.resolver,
          container:,
        )

        container.gate = gate
        container
      end
    end
  end
end
