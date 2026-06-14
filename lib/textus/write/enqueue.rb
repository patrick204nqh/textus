module Textus
  module Write
    # Push a job of a REGISTERED type onto the convergence queue, to be run by
    # drain/serve. The closed allow-list (Jobs::Handlers.registry) is the safety
    # boundary: an unregistered type is refused, so the general runner can never
    # execute arbitrary code. Authority is checked here (the caller must hold the
    # type's required_role, if any) and frozen onto the job's `enqueued_by` — the
    # worker runs it as exactly this role, no escalation via the queue.
    class Enqueue
      extend Textus::Contract::DSL

      verb     :enqueue
      summary  "Push a registered job type onto the convergence queue, to be run by drain/serve."
      surfaces :cli, :mcp
      cli      "enqueue"
      arg :type, String, required: true, positional: true, description: "registered job type (e.g. materialize, re-pull, sweep)"
      arg :args, Hash, positional: true, default: {}, description: "type-specific arguments (e.g. { key: ... } or { scope: ... })"

      def initialize(container:, call:)
        @container = container
        @call = call
      end

      def call(type, args = {})
        entry = Textus::Jobs::Handlers.registry.lookup(type) # raises UsageError for unregistered types
        authorize!(entry)

        job = Textus::Core::Jobs::Job.new(
          type: type, args: args, enqueued_by: @call.role, max_attempts: entry.max_attempts,
        )
        Textus::Ports::Queue.new(root: @container.root).enqueue(job)
        { "protocol" => Textus::PROTOCOL, "ok" => true, "id" => job.id }
      end

      private

      def authorize!(entry)
        required = entry.required_role
        return if required.nil? || @call.role == required

        raise Textus::Error.new(
          "forbidden",
          "role '#{@call.role}' is not authorized to enqueue this job type (requires '#{required}')",
          details: { "role" => @call.role, "required_role" => required },
          exit_code: 77,
        )
      end
    end
  end
end
