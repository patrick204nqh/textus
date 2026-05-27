module Textus
  module Application
    module Writes
      class Accept
        def initialize(ctx:, manifest:, file_store:, envelope_io:, bus:, authorizer:, store:) # rubocop:disable Metrics/ParameterLists
          @ctx         = ctx
          @manifest    = manifest
          @file_store  = file_store
          @envelope_io = envelope_io
          @bus         = bus
          @authorizer  = authorizer
          @store       = store
        end

        def call(pending_key)
          raise ProposalError.new("only human role can accept proposals; got '#{@ctx.role}'") unless @ctx.role == "human"

          env = Textus::Application::Reads::Get.new(
            ctx: @ctx, manifest: @manifest, file_store: @file_store,
          ).call(pending_key)
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
            put_op.call(target, meta: target_meta, body: target_body)
          when "delete"
            delete_op.call(target)
          else
            raise ProposalError.new("unknown action: #{action}")
          end

          delete_op.call(pending_key)

          @bus.publish(:proposal_accepted,
                       store: @store,
                       role: @ctx.role,
                       key: pending_key,
                       target_key: target,
                       correlation_id: @ctx.correlation_id)

          { "protocol" => PROTOCOL, "accepted" => pending_key, "target_key" => target, "action" => action }
        end

        private

        def put_op
          @put_op ||= Textus::Application::Writes::Put.new(
            ctx: @ctx, manifest: @manifest, envelope_io: @envelope_io,
            bus: @bus, authorizer: @authorizer, store: @store
          )
        end

        def delete_op
          @delete_op ||= Textus::Application::Writes::Delete.new(
            ctx: @ctx, manifest: @manifest, envelope_io: @envelope_io,
            bus: @bus, authorizer: @authorizer, store: @store
          )
        end

        def evaluate_promotion!(env, target_key)
          rules = @manifest.rules_for(target_key)
          promote = rules.promote
          return if promote.nil? || promote.requires.empty?

          policy = Textus::Domain::Policy::Promotion.from_names(promote.requires)
          # T9 will replace `store:` here when Policy::Promotion takes
          # reader/lister callables instead of a store handle.
          result = policy.evaluate(entry: env, store: @store)
          return if result.ok?

          raise ProposalError.new(
            "promotion gate failed: #{result.reasons.join("; ")}",
          )
        end
      end
    end
  end
end
