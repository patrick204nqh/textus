# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class Drain < Base
        extend Textus::Contract::DSL

        verb :drain
        summary "Converge everything now: seed produce + retention jobs and drain the queue to empty."
        surfaces :cli, :mcp
        cli "drain"
        arg :prefix, String, description: "restrict convergence to keys under this dotted prefix"
        arg :lane, String, description: "restrict convergence to entries in this lane"

        BURN = :sync

        def initialize(prefix: nil, lane: nil)
          super()
          @prefix = prefix
          @lane = lane
        end

        def self.new(*args, **kwargs)
          return super(**kwargs) unless args.any?

          positional = instance_method(:initialize).parameters.slice(:keyreq, :key).map(&:last)
          mapped = positional.zip(args).to_h
          super(**mapped.merge(kwargs))
        end

        def args
          {
            prefix: @prefix,
            lane: @lane,
          }.compact
        end

        def call(container:, **)
          _ = @prefix
          _ = @lane

          queue = Textus::Ports::Queue.new(root: container.root)
          completed = 0
          failed = 0

          while (leased = queue.lease(worker_id: "drain", lease_ttl: 60))
            begin
              run_queued_job(leased, container)
              queue.ack(leased)
              completed += 1
            rescue StandardError => e
              outcome = queue.fail(leased, error: e.message)
              failed += 1 if outcome == :dead_lettered
            end
          end

          {
            "protocol" => Textus::PROTOCOL,
            "ok" => failed.zero?,
            "completed" => completed,
            "failed" => failed,
          }
        end

        private

        def run_queued_job(leased, container)
          job = leased.job
          entry = Textus::Jobs::Handlers.registry.lookup(job.type)
          entry.handler.call(job: job, container: container)
        end
      end
    end
  end
end
