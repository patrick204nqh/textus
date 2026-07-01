# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module DrainStore
        HANDLES = Dispatch::Contracts::DrainStore
        NEEDS = %i[manifest file_store schemas audit_log job_store layout workflows].freeze

        def self.call(_command, call, deps)
          proxy = Store::ContainerProxy.new(
            manifest: deps.manifest, file_store: deps.file_store,
            schemas: deps.schemas, audit_log: deps.audit_log,
            job_store: deps.job_store, layout: deps.layout,
            workflows: deps.workflows,
            link_edge_store: nil, pipeline: nil, root: deps.layout.root
          )
          queue = Textus::Store::Jobs::Queue.new(store: deps.job_store)
          Textus::Store::Jobs::Planner.seed(container: proxy, queue: queue, role: call.role)
          queue.reclaim(now: Textus::Port::Clock.new.now)
          summary = Textus::Store::Jobs::Worker.for(container: proxy, queue: queue).drain
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => summary.failed.zero?,
                                "completed" => summary.completed, "failed" => summary.failed)
        end
      end
    end
  end
end
