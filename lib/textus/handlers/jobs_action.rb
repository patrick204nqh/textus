module Textus
  module Handlers
    class JobsAction
      def initialize(job_store:)
        @job_store = job_store
      end

      def call(command, _call)
        queue = Textus::Store::Jobs::Queue.new(store: @job_store)
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
