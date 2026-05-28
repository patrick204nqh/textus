require_relative "authority_gate"

module Textus
  module Application
    module Writes
      class Reject
        include AuthorityGate

        def initialize(ctx:, ports:, envelope_io:, authorizer:, hook_context:)
          @ctx          = ctx
          @ports        = ports
          @manifest     = ports.manifest
          @envelope_io  = envelope_io
          @bus          = ports.event_bus
          @authorizer   = authorizer
          @hook_context = hook_context
        end

        def call(pending_key)
          assert_accept_authority!("reject")

          mentry = @manifest.resolver.resolve(pending_key).entry
          unless mentry.in_proposal_zone?
            raise ProposalError.new("reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.zone})")
          end

          env = Textus::Application::Reads::Get.new(
            ctx: @ctx, ports: @ports,
          ).call(pending_key)
          proposal = env.meta&.dig("proposal") or
            raise ProposalError.new("entry has no proposal block: #{pending_key}")
          target_key = proposal["target_key"] or
            raise ProposalError.new("proposal missing target_key")

          Textus::Application::Writes::Delete.new(
            ctx: @ctx, ports: @ports, envelope_io: @envelope_io,
            authorizer: @authorizer, hook_context: @hook_context
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
