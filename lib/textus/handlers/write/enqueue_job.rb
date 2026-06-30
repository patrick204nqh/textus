module Textus
  module Handlers
    module Write
      module EnqueueJob
        HANDLES = Dispatch::Contracts::EnqueueJob
        NEEDS   = %i[job_store].freeze

        def self.call(command, call, deps)
          action_class = Textus::Jobs.fetch(command.type.to_s)

          if action_class.const_defined?(:REQUIRED_ROLE) && call.role != action_class::REQUIRED_ROLE
            return Value::Result.failure(:forbidden,
                                         "role '#{call.role}' is not authorized to enqueue this job type",
                                         details: { "role" => call.role, "required_role" => action_class::REQUIRED_ROLE })
          end

          job = Textus::Store::Jobs::Queue::Job.new(type: command.type, args: command.args, role: call.role, max_attempts: 3)
          Textus::Store::Jobs::Queue.new(store: deps.job_store).enqueue(job)
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "id" => job.id)
        rescue Textus::UsageError
          Value::Result.failure(:usage_error, "unregistered job type '#{command.type}'")
        end
      end
    end
  end
end
