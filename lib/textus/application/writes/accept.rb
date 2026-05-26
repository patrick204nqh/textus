module Textus
  module Application
    module Writes
      class Accept
        def initialize(ctx:, bus:)
          @ctx = ctx
          @bus = bus
        end

        def call(pending_key)
          raise ProposalError.new("only human role can accept proposals; got '#{@ctx.role}'") unless @ctx.role == "human"

          env = @ctx.store.reader.get(pending_key)
          proposal = env.meta["proposal"] or raise ProposalError.new("entry has no proposal block: #{pending_key}")
          target = proposal["target_key"] or raise ProposalError.new("proposal missing target_key")
          action = proposal["action"] || "put"

          evaluate_promotion!(env, target)

          case action
          when "put"
            # Nested proposal "frontmatter" — the meta to write to the accepted
            # target. Not related to the removed intake-handler legacy bridge.
            target_meta = env.meta["frontmatter"] || {}
            target_body = env.body
            Textus::Application::Writes::Put.new(ctx: @ctx, bus: @bus).call(target, meta: target_meta, body: target_body)
          when "delete"
            Textus::Application::Writes::Delete.new(ctx: @ctx, bus: @bus).call(target)
          else
            raise ProposalError.new("unknown action: #{action}")
          end

          Textus::Application::Writes::Delete.new(ctx: @ctx, bus: @bus).call(pending_key)

          @bus.publish(:proposal_accepted,
                       store: @ctx.with_role(@ctx.role),
                       key: pending_key,
                       target_key: target,
                       correlation_id: @ctx.correlation_id)

          { "protocol" => PROTOCOL, "accepted" => pending_key, "target_key" => target, "action" => action }
        end

        private

        def evaluate_promotion!(env, target_key)
          rules = @ctx.store.manifest.rules_for(target_key)
          promote = rules.promote
          return if promote.nil? || promote.requires.empty?

          policy = Textus::Domain::Policy::Promotion.from_names(promote.requires)
          result = policy.evaluate(entry: env, store: @ctx.store)
          return if result.ok?

          raise ProposalError.new(
            "promotion gate failed: #{result.reasons.join("; ")}",
          )
        end
      end
    end
  end
end
