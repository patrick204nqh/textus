# frozen_string_literal: true

module Textus
  module Action
    class Enqueue < Base
      verb :enqueue
      summary "Push a registered job type onto the convergence queue, to be run by drain/serve."
      surfaces :cli, :mcp
      cli "enqueue"
      arg :type, String, required: true, positional: true,
                         description: "registered job type (e.g. materialize, re-pull, sweep)"
      arg :args, Hash, default: {},
                       description: "type-specific arguments (e.g. { key: ... } or { scope: ... })"

      def self.call(container:, call:, type:, args: {})
        action_class = Textus::Jobs.fetch(type.to_s)

        if action_class.const_defined?(:REQUIRED_ROLE) && call.role != action_class::REQUIRED_ROLE
          return Failure(code: :forbidden,
                         message: "role '#{call.role}' is not authorized to enqueue this job type",
                         details: { "role" => call.role, "required_role" => action_class::REQUIRED_ROLE })
        end

        job = Textus::Store::Jobs::Queue::Job.new(
          type: type,
          args: args,
          role: call.role,
          max_attempts: 3,
        )
        Textus::Store::Jobs::Queue.new(store: container.job_store).enqueue(job)
        Success({ "protocol" => Textus::PROTOCOL, "ok" => true, "id" => job.id })
      rescue Textus::UsageError
        Failure(code: :usage_error, message: "unregistered job type '#{type}'")
      end
    end
  end
end
