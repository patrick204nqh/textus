require_relative "authority_gate"

module Textus
  module Application
    module Writes
      module Accept
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
            @file_store   = caps.file_store
            @schemas      = caps.schemas
            @writer       = writer
            @events       = caps.events
            @authorizer   = caps.authorizer
            @hook_context = hook_context
          end

          def call(pending_key)
            assert_accept_authority!("accept")

            env = Textus::Application::Reads::Get::Impl.new(
              ctx: @ctx, caps: @caps,
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

            @events.publish(:proposal_accepted,
                            ctx: @hook_context,
                            key: pending_key,
                            target_key: target)

            { "protocol" => PROTOCOL, "accepted" => pending_key, "target_key" => target, "action" => action }
          end

          private

          def put_op
            @put_op ||= Textus::Application::Writes::Put::Impl.new(
              ctx: @ctx, caps: @caps, writer: @writer,
              hook_context: @hook_context
            )
          end

          def delete_op
            @delete_op ||= Textus::Application::Writes::Delete::Impl.new(
              ctx: @ctx, caps: @caps, writer: @writer,
              hook_context: @hook_context
            )
          end

          def evaluate_promotion!(env, target_key)
            rules = @manifest.rules.for(target_key)
            promote = rules.promote
            return if promote.nil? || promote.requires.empty?

            policy = Textus::Domain::Policy::Promotion.from_names(promote.requires)
            result = policy.evaluate(
              entry: env, schemas: @schemas, manifest: @manifest, role: @ctx.role,
            )
            return if result.ok?

            raise ProposalError.new(
              "promotion gate failed: #{result.reasons.join("; ")}",
            )
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:accept, Textus::Application::Writes::Accept, caps: :write)
