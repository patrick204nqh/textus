module Textus
  module Handlers
    module Maintenance
      class DrainStore
        def initialize(container:, job_store:)
          @container = container
          @job_store = job_store
        end

        def call(_command, call)
          queue = Textus::Store::Jobs::Queue.new(store: @job_store)
          Textus::Store::Jobs::Planner.seed(container: @container, queue: queue, role: call.role)
          queue.reclaim(now: Textus::Port::Clock.new.now)
          summary = Textus::Store::Jobs::Worker.for(container: @container, queue: queue).drain
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => summary.failed.zero?,
                                "completed" => summary.completed, "failed" => summary.failed)
        end
      end
    end
  end
end
