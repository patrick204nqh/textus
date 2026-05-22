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

          env = @ctx.store.get(pending_key)
          proposal = env["_meta"]["proposal"] or raise ProposalError.new("entry has no proposal block: #{pending_key}")
          target = proposal["target_key"] or raise ProposalError.new("proposal missing target_key")
          action = proposal["action"] || "put"

          case action
          when "put"
            target_meta = env["_meta"]["frontmatter"] || {}
            target_body = env["body"]
            Composition.writes_put(@ctx).call(target, meta: target_meta, body: target_body)
          when "delete"
            Composition.writes_delete(@ctx).call(target)
          else
            raise ProposalError.new("unknown action: #{action}")
          end

          Composition.writes_delete(@ctx).call(pending_key)

          store_view = Store::View.new(@ctx.store)
          @bus.publish(:accepted,
                       store: store_view,
                       key: pending_key,
                       target_key: target,
                       correlation_id: @ctx.correlation_id)

          { "protocol" => PROTOCOL, "accepted" => pending_key, "target_key" => target, "action" => action }
        end
      end
    end
  end
end
