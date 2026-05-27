module Textus
  module Application
    module Writes
      class Reject
        def initialize(ctx:, envelope_io:)
          @ctx = ctx
          @envelope_io = envelope_io
        end

        def call(pending_key)
          raise ProposalError.new("only human role can reject proposals; got '#{@ctx.role}'") unless @ctx.role == "human"

          mentry = @ctx.manifest.resolve(pending_key).entry
          unless mentry.in_proposal_zone?
            raise ProposalError.new("reject: '#{pending_key}' is not in a proposal zone (zone=#{mentry.zone})")
          end

          env = Textus::Application::Reads::Get.new(ctx: @ctx, manifest: @ctx.manifest, file_store: @ctx.file_store).call(pending_key)
          proposal = env.meta&.dig("proposal") or
            raise ProposalError.new("entry has no proposal block: #{pending_key}")
          target_key = proposal["target_key"] or
            raise ProposalError.new("proposal missing target_key")

          Textus::Application::Writes::Delete.new(ctx: @ctx, envelope_io: @envelope_io).call(pending_key, suppress_events: true)

          @ctx.bus.publish(:proposal_rejected,
                           store: @ctx.with_role(@ctx.role),
                           key: pending_key,
                           target_key: target_key,
                           correlation_id: @ctx.correlation_id)

          { "protocol" => PROTOCOL, "rejected" => pending_key, "target_key" => target_key }
        end
      end
    end
  end
end
