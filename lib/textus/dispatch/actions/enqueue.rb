# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class Enqueue < WriteVerb
        extend Textus::Contract::DSL

        verb :enqueue
        summary "Push a registered job type onto the convergence queue, to be run by drain/serve."
        surfaces :cli, :mcp
        cli "enqueue"
        arg :type, String, required: true, positional: true,
                           description: "registered job type (e.g. materialize, re-pull, sweep)"
        arg :args, Hash, default: {},
                         description: "type-specific arguments (e.g. { key: ... } or { scope: ... })"

        BURN = :sync

        def initialize(type:, args: {})
          super()
          @type = type
          @job_args = args
        end

        def args
          { type: @type, args: @job_args }
        end

        def call(container:, call:)
          action_class = begin
            Textus::Dispatcher.fetch(@type.to_sym)
          rescue Textus::UsageError
            raise Textus::UsageError.new("unregistered job type '#{@type}'")
          end
          if action_class.const_defined?(:REQUIRED_ROLE) && call.role != action_class::REQUIRED_ROLE
            raise Textus::Error.new(
              "forbidden",
              "role '#{call.role}' is not authorized to enqueue this job type (requires '#{action_class::REQUIRED_ROLE}')",
              details: { "role" => call.role, "required_role" => action_class::REQUIRED_ROLE },
              exit_code: 77,
            )
          end

          job = Textus::Core::Jobs::Job.new(
            type: @type,
            args: @job_args,
            enqueued_by: call.role,
            max_attempts: 3,
          )
          Textus::Ports::Queue.new(root: container.root).enqueue(job)
          { "protocol" => Textus::PROTOCOL, "ok" => true, "id" => job.id }
        end
      end
    end
  end
end
