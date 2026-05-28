require_relative "authority_gate"

module Textus
  module Application
    module Writes
      module Reject
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(
            ctx: ctx, caps: caps,
            writer: session.envelope_writer,
            hook_context: session.hook_context
          ).call(*, **)
        end

        class Impl
          include AuthorityGate

          def initialize(ctx:, caps:, writer:, hook_context:)
            @ctx          = ctx
            @caps         = caps
            @manifest     = caps.manifest
            @writer       = writer
            @events       = caps.events
            @authorizer   = caps.authorizer
            @hook_context = hook_context
          end

          def call(pending_key)
            assert_accept_authority!("reject")

            mentry = @manifest.resolver.resolve(pending_key).entry
            unless mentry.in_proposal_zone?
              raise ProposalError.new("reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.zone})")
            end

            env = Textus::Application::Reads::Get::Impl.new(
              ctx: @ctx, caps: @caps,
            ).call(pending_key)
            proposal = env.meta&.dig("proposal") or
              raise ProposalError.new("entry has no proposal block: #{pending_key}")
            target_key = proposal["target_key"] or
              raise ProposalError.new("proposal missing target_key")

            Textus::Application::Writes::Delete::Impl.new(
              ctx: @ctx, caps: @caps, writer: @writer,
              hook_context: @hook_context
            ).call(pending_key, suppress_events: true)

            @events.publish(:proposal_rejected,
                            ctx: @hook_context,
                            key: pending_key,
                            target_key: target_key)

            { "protocol" => PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:reject, Textus::Application::Writes::Reject, caps: :write)
