# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module JobsAction
        HANDLES = Dispatch::Contracts::JobsAction
        NEEDS = %i[job_store].freeze

        def self.call(command, _call, deps)
          queue = Textus::Store::Jobs::Queue.new(store: deps.job_store)
          case command.action
          when "retry" then queue.retry_failed(command.job_id)
          when "purge" then queue.purge(command.state)
          end
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true,
                                "state" => command.state, "jobs" => queue.list(command.state))
        end
      end
    end
  end
end
