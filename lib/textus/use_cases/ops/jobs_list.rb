# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module JobsList
        HANDLES = Dispatch::Contracts::JobsList
        NEEDS = %i[job_store].freeze

        def self.call(command, _call, deps)
          queue = Textus::Store::Jobs::Queue.new(store: deps.job_store)
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true,
                                "state" => command.state, "jobs" => queue.list(command.state))
        end
      end
    end
  end
end
