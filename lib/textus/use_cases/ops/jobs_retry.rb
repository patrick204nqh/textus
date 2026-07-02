# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module JobsRetry
        HANDLES = Dispatch::Contracts::JobsRetry
        NEEDS = %i[job_store].freeze

        def self.call(command, _call, deps)
          queue = Textus::Store::Jobs::Queue.new(store: deps.job_store)
          queue.retry_failed(command.job_id)
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "job_id" => command.job_id)
        end
      end
    end
  end
end
