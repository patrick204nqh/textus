# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module BootStore
        HANDLES = Dispatch::Contracts::BootStore
        NEEDS = %i[manifest file_system schemas audit_log layout pipeline].freeze

        def self.call(_command, _call, deps)
          proxy = Store::Infrastructure.build(
            manifest: deps.manifest, file_system: deps.file_system,
            schemas: deps.schemas, audit_log: deps.audit_log,
            layout: deps.layout, root: deps.layout.root,
            pipeline: deps.pipeline
          )
          Value::Result.success(Textus::Boot.build(container: proxy))
        end
      end
    end
  end
end
