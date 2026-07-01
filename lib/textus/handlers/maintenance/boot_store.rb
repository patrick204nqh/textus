module Textus
  module Handlers
    module Maintenance
      module BootStore
        HANDLES = Dispatch::Contracts::BootStore
        NEEDS   = %i[manifest file_store schemas audit_log layout pipeline].freeze

        def self.call(_command, _call, deps)
          proxy = Store::ContainerProxy.new(
            manifest: deps.manifest, file_store: deps.file_store,
            schemas: deps.schemas, audit_log: deps.audit_log,
            layout: deps.layout, pipeline: deps.pipeline,
            job_store: nil, workflows: nil,
            link_edge_store: nil, root: deps.layout.root
          )
          Value::Result.success(Textus::Boot.build(container: proxy))
        end
      end
    end
  end
end
