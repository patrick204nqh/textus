module Textus
  module Application
    module Read
      # Composes pure `Read::Get` with the refresh orchestrator: runs Get
      # to obtain the envelope and freshness verdict, then if the verdict
      # is stale and the rule's `on_stale` policy demands action, hands
      # off to the orchestrator. Use for interactive reads where the
      # caller wants the freshest obtainable envelope.
      #
      # Pure reads (build, projection, schema tooling) should use
      # `Read::Get` directly; it has no orchestrator dependency.
      class GetOrRefresh
        def initialize(container:, call:, hook_context: nil, get: nil, orchestrator: nil)
          @container    = container
          @call         = call
          @manifest     = container.manifest
          @hook_context = hook_context
          @get          = get || Read::Get.new(container: container, call: call)
          @orchestrator = orchestrator || build_orchestrator
        end

        private

        def build_orchestrator
          worker = Textus::Application::Write::RefreshWorker.new(
            container: @container, call: @call, hook_context: @hook_context,
          )
          Textus::Application::Write::RefreshOrchestrator.new(
            worker: worker, store_root: @container.root, events: @container.events,
            ctx: @call, hook_context: @hook_context
          )
        end

        public

        def call(key)
          envelope = @get.call(key)
          return nil if envelope.nil?
          return envelope unless envelope.freshness&.stale

          policy_set = @manifest.rules.for(key)
          refresh_policy = policy_set.refresh
          return envelope if refresh_policy.nil?

          policy = refresh_policy.to_freshness_policy
          verdict = Textus::Domain::Freshness::Verdict.stale(envelope.freshness.reason)
          action = policy.decide(verdict)
          outcome = @orchestrator.execute(action, key: key)

          case outcome
          when Textus::Domain::Outcome::Skipped
            envelope
          when Textus::Domain::Outcome::Refreshed
            outcome.envelope.with(
              freshness: Textus::Domain::Freshness.build(stale: false, reason: nil, refreshing: false),
            )
          when Textus::Domain::Outcome::Detached
            envelope.with(freshness: envelope.freshness.with(refreshing: true))
          when Textus::Domain::Outcome::Failed
            envelope.with(
              freshness: envelope.freshness.with(refresh_error: outcome.error.message),
            )
          end
        end
      end
    end
  end
end
