# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module DoctorStore
        HANDLES = Dispatch::Contracts::DoctorStore
        NEEDS = %i[manifest layout pipeline file_store schemas audit_log].freeze

        def self.call(command, call, deps)
          proxy = Store::Infrastructure.new(
            manifest: deps.manifest, file_store: deps.file_store,
            layout: deps.layout, pipeline: deps.pipeline,
            audit_log: deps.audit_log, schemas: deps.schemas,
            job_store: nil, link_edge_store: nil,
            workflows: nil,
            root: deps.layout.root, reader: nil, writer: nil,
            event_bus: nil, ttl_evaluator: nil,
            trace_buffer: nil
          )
          Value::Result.success(Textus::Doctor.build(container: proxy, checks: command.checks, role: call.role))
        end
      end
    end
  end
end
