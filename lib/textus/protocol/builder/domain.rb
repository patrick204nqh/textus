module Textus
  module Protocol
    class Builder
      class Domain
        Components = Data.define(:manifest, :schemas, :workflows, :workflow_registry)

        def call(root, layout:)
          manifest = Manifest.load(root)
          schemas = Schema::Registry.new(layout.schemas_dir)
          workflows = Workflow::Registry.load_all(root)
          workflow_registry = Workflow::Registry.new(workflows)
          Components.new(manifest:, schemas:, workflows:, workflow_registry:)
        end
      end
    end
  end
end
