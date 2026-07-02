module Textus
  module UseCases
    module Write
      module EnqueueJob
        HANDLES = Dispatch::Contracts::EnqueueJob
        NEEDS = %i[job_store].freeze

        def self.call(command, call, deps)
          Store::Jobs::Registry.fetch(command.type.to_s)

          required = Store::Jobs::Registry.required_role(command.type.to_s)
          if required && call.role != required
            return Value::Result.failure(:forbidden,
                                         "role '#{call.role}' is not authorized to enqueue this job type",
                                         details: { "role" => call.role, "required_role" => required })
          end

          job = Textus::Store::Jobs::Queue::Job.new(type: command.type, args: command.args, role: call.role, max_attempts: 3)
          Textus::Store::Jobs::Queue.new(store: deps.job_store).enqueue(job)
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "id" => job.id)
        rescue Store::Jobs::Registry::UnknownJob
          Value::Result.failure(:usage_error, "unregistered job type '#{command.type}'")
        end
      end
    end
  end
end
