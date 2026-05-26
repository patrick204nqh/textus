module Textus
  module Application
    module Reads
      # Composes pure `Reads::Get` with the refresh orchestrator: runs Get
      # to obtain the envelope and freshness verdict, then if the verdict
      # is stale and the rule's `on_stale` policy demands action, hands
      # off to the orchestrator. Use for interactive reads where the
      # caller wants the freshest obtainable envelope.
      #
      # Pure reads (build, projection, schema tooling) should use
      # `Reads::Get` directly; it has no orchestrator dependency.
      class GetOrRefresh
        def initialize(ctx:, get:, orchestrator:)
          @ctx          = ctx
          @get          = get
          @orchestrator = orchestrator
        end

        def call(key)
          envelope = @get.call(key)
          return nil if envelope.nil?
          return envelope unless envelope.freshness["stale"]

          policy_set = @ctx.store.manifest.rules_for(key)
          refresh_policy = policy_set.refresh
          return envelope if refresh_policy.nil?

          policy = refresh_policy.to_freshness_policy
          verdict = Textus::Domain::Freshness::Verdict.stale(envelope.freshness["stale_reason"])
          action = policy.decide(verdict)
          outcome = @orchestrator.execute(action, key: key)

          case outcome
          when Textus::Domain::Outcome::Skipped
            envelope
          when Textus::Domain::Outcome::Refreshed
            outcome.envelope.with(
              freshness: { "stale" => false, "stale_reason" => nil, "refreshing" => false },
            )
          when Textus::Domain::Outcome::Detached
            envelope.with(freshness: envelope.freshness.merge("refreshing" => true))
          when Textus::Domain::Outcome::Failed
            envelope.with(
              freshness: envelope.freshness.merge("refresh_error" => outcome.error.message),
            )
          end
        end
      end
    end
  end
end
