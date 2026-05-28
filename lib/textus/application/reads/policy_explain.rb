module Textus
  module Application
    module Reads
      # For one key, surface every matching policy block along with the
      # per-slot effective value (which loses ties win-by-specificity).
      module PolicyExplain
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(caps: caps).call(*, **)
        end

        class Impl
          def initialize(caps:)
            @manifest = caps.manifest
          end

          def call(key:)
            policies = @manifest.rules
            matching = policies.explain(key)
            winners  = policies.for(key)

            {
              key: key,
              matched_blocks: matching.map do |b|
                {
                  match: b.match,
                  refresh: !b.refresh.nil?,
                  handler_allowlist: !b.handler_allowlist.nil?,
                  promote: !b.promote.nil?,
                }
              end,
              effective: {
                refresh: winners.refresh && {
                  ttl_seconds: winners.refresh.ttl_seconds,
                  on_stale: winners.refresh.on_stale,
                },
                handler_allowlist: winners.handler_allowlist&.handlers,
                promotion: winners.promote && { requires: winners.promote.requires },
              },
            }
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:policy_explain, Textus::Application::Reads::PolicyExplain, caps: :read)
