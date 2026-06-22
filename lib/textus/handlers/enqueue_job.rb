module Textus
  module Handlers
    class EnqueueJob
      def initialize(job_store:)
        @job_store = job_store
      end

      def call(command, call)
        action_class = Textus::Jobs.fetch(command.type.to_s)

        if action_class.const_defined?(:REQUIRED_ROLE) && call.role != action_class::REQUIRED_ROLE
          return Result.failure(:forbidden,
                                "role '#{call.role}' is not authorized to enqueue this job type",
                                details: { "role" => call.role, "required_role" => action_class::REQUIRED_ROLE })
        end

        job = Textus::Store::Jobs::Queue::Job.new(type: command.type, args: command.args, role: call.role, max_attempts: 3)
        Textus::Store::Jobs::Queue.new(store: @job_store).enqueue(job)
        Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "id" => job.id)
      rescue Textus::UsageError
        Result.failure(:usage_error, "unregistered job type '#{command.type}'")
      end
    end
  end
end
