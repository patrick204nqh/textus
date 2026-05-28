require_relative "authority_gate"

module Textus
  module Application
    module Write
      class Reject
        include AuthorityGate

        def initialize(container:, call:, hook_context:)
          @container    = container
          @call         = call
          @ctx          = call # AuthorityGate uses @ctx.role
          @manifest     = container.manifest
          @file_store   = container.file_store
          @events       = container.events
          @authorizer   = container.authorizer
          @hook_context = hook_context
        end

        def call(pending_key)
          assert_accept_authority!("reject")

          mentry = @manifest.resolver.resolve(pending_key).entry
          unless mentry.in_proposal_zone?
            raise ProposalError.new("reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.zone})")
          end

          env = Textus::Application::Read::Get::Impl.new(
            ctx: @call, caps: read_caps_struct,
          ).call(pending_key)
          proposal = env.meta&.dig("proposal") or
            raise ProposalError.new("entry has no proposal block: #{pending_key}")
          target_key = proposal["target_key"] or
            raise ProposalError.new("proposal missing target_key")

          delete_op.call(pending_key, suppress_events: true)

          @events.publish(:proposal_rejected,
                          ctx: @hook_context,
                          key: pending_key,
                          target_key: target_key)

          { "protocol" => PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
        end

        private

        def delete_op
          @delete_op ||= Textus::Application::Write::Delete.new(
            container: @container, call: @call, hook_context: @hook_context,
          )
        end

        def read_caps_struct
          @read_caps_struct ||= Struct.new(:manifest, :file_store, :authorizer).new(
            @manifest, @file_store, @authorizer
          )
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:reject, Textus::Application::Write::Reject, caps: :write)
