module Textus
  class Store
    module Jobs
      class Worker
        Summary = Struct.new(:completed, :failed, keyword_init: true)

        def self.for(container:, queue:)
          new(queue: queue, container: container,
              lease_ttl: container.manifest.data.worker_config[:lease_ttl])
        end

        def initialize(queue:, container:, lease_ttl: 60)
          @queue     = queue
          @container = container
          @lease_ttl = lease_ttl
        end

        def drain(worker_id: "drain-#{Process.pid}")
          completed = 0
          failed    = 0
          loop do
            leased = @queue.lease(worker_id: worker_id, lease_ttl: @lease_ttl)
            break unless leased

            case run_one(leased)
            when :completed     then completed += 1
            when :dead_lettered then failed += 1
            end
          end
          Summary.new(completed: completed, failed: failed)
        end

        def drain_pool(pool: 4)
          summaries = []
          mutex     = Mutex.new
          threads   = Array.new(pool) do |i|
            Thread.new do
              s = drain(worker_id: "pool-#{Process.pid}-#{i}")
              mutex.synchronize { summaries << s }
            end
          end
          threads.each(&:join)
          Summary.new(completed: summaries.sum(&:completed), failed: summaries.sum(&:failed))
        end

        private

        def run_one(leased)
          job    = leased.job
          klass  = Textus::Jobs.fetch(job.type)
          action = if klass.instance_method(:initialize).parameters.any?
                     klass.new(**job.args.transform_keys(&:to_sym))
                   else
                     klass.new
                   end
          call   = Textus::Value::Call.build(
            role: job.role || Textus::Value::Role::AUTOMATION,
            correlation_id: SecureRandom.uuid,
          )
          action.call(container: @container, call: call)
          @queue.ack(leased)
          :completed
        rescue StandardError => e
          @queue.fail(leased, error: e.message)
        end
      end
    end
  end
end
