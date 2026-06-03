module Textus
  module Write
    class Accept
      extend Textus::Contract::DSL

      verb :accept
      summary "apply a queued proposal to its target zone; requires the author capability"
      surfaces :cli, :mcp
      cli "accept"
      arg :pending_key, String, required: true, positional: true, description: "the queued proposal's key"

      def initialize(container:, call:)
        @container = container
        @call      = call
        @manifest  = container.manifest
        @schemas   = container.schemas
        @events    = container.events
      end

      def call(pending_key)
        env = Textus::Read::Get.new(container: @container, call: @call).call(pending_key)
        proposal = env.meta["proposal"] or raise ProposalError.new("entry has no proposal block: #{pending_key}")
        target = proposal["target_key"] or raise ProposalError.new("proposal missing target_key")
        action = proposal["action"] || "put"

        guard.for(:accept, target).check!(
          Textus::Domain::Policy::Evaluation.new(
            actor: @call.role, transition: :accept, origin: pending_key,
            target: target, envelope: env, manifest: @manifest
          ),
        )

        case action
        when "put"
          put_op.call(target, meta: env.meta["frontmatter"] || {}, body: env.body)
        when "delete"
          delete_op.call(target)
        else
          raise ProposalError.new("unknown action: #{action}")
        end

        delete_op.call(pending_key)
        @events.publish(:proposal_accepted, ctx: hook_context, key: pending_key, target_key: target)
        { "protocol" => PROTOCOL, "accepted" => pending_key, "target_key" => target, "action" => action }
      end

      private

      def guard
        @guard ||= Textus::Domain::Policy::GuardFactory.new(manifest: @manifest, schemas: @schemas)
      end

      def hook_context = @hook_context ||= Textus::Hooks::Context.for(container: @container, call: @call)
      def put_op       = @put_op ||= Textus::Write::Put.new(container: @container, call: @call)
      def delete_op    = @delete_op ||= Textus::Write::Delete.new(container: @container, call: @call)
    end
  end
end
