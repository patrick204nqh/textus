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
          entry = Textus::Dispatch::Planner::Handlers.registry.lookup(@type)
          authorize!(entry, call)

          job = Textus::Core::Jobs::Job.new(
            type: @type,
            args: @job_args,
            enqueued_by: call.role,
            max_attempts: entry.max_attempts,
          )
          Textus::Ports::Queue.new(root: container.root).enqueue(job)
          { "protocol" => Textus::PROTOCOL, "ok" => true, "id" => job.id }
        end

        private

        def authorize!(entry, call)
          required = entry.required_role
          return if required.nil? || call.role == required

          raise Textus::Error.new(
            "forbidden",
            "role '#{call.role}' is not authorized to enqueue this job type (requires '#{required}')",
            details: { "role" => call.role, "required_role" => required },
            exit_code: 77,
          )
        end
      end
    end
  end
end
