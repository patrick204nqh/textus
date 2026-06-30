module Textus
  module Handlers
    module Maintenance
      module DoctorStore
        HANDLES = Dispatch::Contracts::DoctorStore
        NEEDS   = %i[manifest file_store layout pipeline audit_log schemas].freeze

        def self.call(command, call, deps)
          proxy = Store::ContainerProxy.new(
            manifest: deps.manifest, file_store: deps.file_store,
            layout: deps.layout, pipeline: deps.pipeline,
            audit_log: deps.audit_log, schemas: deps.schemas,
            job_store: nil, workflows: nil, root: deps.layout.root
          )
          Value::Result.success(Textus::Doctor.build(container: proxy, checks: command.checks, role: call.role))
        end
      end
    end
  end
end
