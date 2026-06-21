# frozen_string_literal: true

module Textus
  module Action
    class Jobs < Base
      extend Textus::Contract::DSL

      verb :jobs
      summary "List queued jobs by state; retry a dead-lettered job or purge a state."
      surfaces :cli, :mcp
      cli "jobs"
      arg :state, String, default: "ready", description: "ready|leased|done|failed"
      arg :action, String, default: nil, description: "retry|purge (optional)"
      arg :job_id, String, default: nil, description: "job id (required for action=retry)"

      def self.call(container:, call:, state: "ready", action: nil, job_id: nil)
        queue = Textus::Store::Jobs::Queue.new(store: container.job_store)
        case action
        when "retry"
          queue.retry_failed(job_id)
        when "purge"
          queue.purge(state)
        end

        { "protocol" => Textus::PROTOCOL, "ok" => true, "state" => state, "jobs" => queue.list(state) }
      end
    end
  end
end
