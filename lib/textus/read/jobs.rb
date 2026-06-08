module Textus
  module Read
    # Inspect and operate the job queue: list ids by state, retry a dead-lettered
    # job, or purge a state. The agent's window into deferred convergence work.
    class Jobs
      extend Textus::Contract::DSL

      verb     :jobs
      summary  "List queued jobs by state; retry a dead-lettered job or purge a state."
      surfaces :cli, :mcp
      cli      "jobs"
      arg :state,  String, default: "ready", description: "ready|leased|done|failed"
      arg :action, String, default: nil, description: "retry|purge (optional)"
      arg :job_id, String, default: nil, description: "job id (required for action=retry)"

      def initialize(container:, call:)
        @container = container
        @call = call
      end

      def call(state: "ready", action: nil, job_id: nil)
        queue = Textus::Ports::Queue.new(root: @container.root)
        case action
        when "retry" then queue.retry_failed(job_id)
        when "purge" then queue.purge(state)
        end
        { "protocol" => Textus::PROTOCOL, "ok" => true, "state" => state, "jobs" => queue.list(state) }
      end
    end
  end
end
