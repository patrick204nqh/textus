module Textus
  module Application
    module Writes
      class Reject
        def initialize(ctx:, manifest:, file_store:, envelope_io:, bus:, authorizer:, hook_context:) # rubocop:disable Metrics/ParameterLists
          @ctx          = ctx
          @manifest     = manifest
          @file_store   = file_store
          @envelope_io  = envelope_io
          @bus          = bus
          @authorizer   = authorizer
          @hook_context = hook_context
        end

        def call(pending_key)
          unless @manifest.role_kind(@ctx.role) == :accept_authority
            authority = @manifest.roles_with_kind(:accept_authority).first || "human"
            raise ProposalError.new("only #{authority} role can reject proposals; got '#{@ctx.role}'")
          end

          mentry = @manifest.resolver.resolve(pending_key).entry
          unless mentry.in_proposal_zone?
            raise ProposalError.new("reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.zone})")
          end

          env = Textus::Application::Reads::Get.new(
            ctx: @ctx, manifest: @manifest, file_store: @file_store,
          ).call(pending_key)
          proposal = env.meta&.dig("proposal") or
            raise ProposalError.new("entry has no proposal block: #{pending_key}")
          target_key = proposal["target_key"] or
            raise ProposalError.new("proposal missing target_key")

          Textus::Application::Writes::Delete.new(
            ctx: @ctx, manifest: @manifest, envelope_io: @envelope_io,
            bus: @bus, authorizer: @authorizer, hook_context: @hook_context
          ).call(pending_key, suppress_events: true)

          @bus.publish(:proposal_rejected,
                       ctx: @hook_context,
                       key: pending_key,
                       target_key: target_key)

          { "protocol" => PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
        end
      end
    end
  end
end
