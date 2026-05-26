module Textus
  module Application
    module Reads
      # Pure read: returns the on-disk envelope annotated with a freshness
      # verdict. Never triggers refresh; never invokes the orchestrator.
      #
      # For interactive reads that want refresh-on-stale, use
      # `Reads::GetOrRefresh`, which composes this with the orchestrator.
      class Get
        def initialize(ctx:, evaluator: Textus::Domain::Freshness::Evaluator)
          @ctx       = ctx
          @evaluator = evaluator
        end

        def call(key)
          envelope = @ctx.store.reader.read_raw_envelope(key)
          return nil if envelope.nil?

          policy_set = @ctx.store.manifest.rules_for(key)
          refresh_policy = policy_set.refresh
          return annotate_fresh(envelope) if refresh_policy.nil?

          policy = refresh_policy.to_freshness_policy
          verdict = @evaluator.call(policy, envelope, now: @ctx.now)

          envelope.with(freshness: Textus::Domain::Freshness.build(
            stale: verdict.stale?,
            reason: verdict.reason,
            refreshing: false,
          ))
        end

        private

        def annotate_fresh(envelope)
          envelope.with(freshness: Textus::Domain::Freshness.build(
            stale: false, reason: nil, refreshing: false,
          ))
        end
      end
    end
  end
end
