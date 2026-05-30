module Textus
  module Read
    # Composes pure `Read::Get` with the fetch orchestrator: runs Get
    # to obtain the envelope and freshness verdict, then if the verdict
    # is stale and the rule's `on_stale` policy demands action, hands
    # off to the orchestrator. Use for interactive reads where the
    # caller wants the freshest obtainable envelope.
    #
    # Pure reads (build, projection, schema tooling) should use
    # `Read::Get` directly; it has no orchestrator dependency.
    class GetOrFetch
      def initialize(container:, call:, get: nil, orchestrator: nil)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @get          = get || Read::Get.new(container: container, call: call)
        @orchestrator = orchestrator || build_orchestrator
      end

      private

      def hook_context
        @hook_context ||= Textus::Hooks::Context.for(container: @container, call: @call)
      end

      def build_orchestrator
        worker = Textus::Write::FetchWorker.new(
          container: @container, call: @call,
        )
        Textus::Write::FetchOrchestrator.new(
          worker: worker, store_root: @container.root, events: @container.events,
          hook_context: hook_context
        )
      end

      public

      def call(key)
        envelope = @get.call(key)
        return nil if envelope.nil?
        return envelope unless envelope.freshness&.stale

        policy_set = @manifest.rules.for(key)
        fetch_policy = policy_set.fetch
        return envelope if fetch_policy.nil?

        policy = fetch_policy.to_freshness_policy
        verdict = Textus::Domain::Freshness::Verdict.stale(envelope.freshness.reason)
        action = policy.decide(verdict)
        outcome = @orchestrator.execute(action, key: key)

        case outcome
        when Textus::Domain::Outcome::Skipped
          envelope
        when Textus::Domain::Outcome::Fetched
          outcome.envelope.with(
            freshness: Textus::Domain::Freshness.build(stale: false, reason: nil, fetching: false),
          )
        when Textus::Domain::Outcome::Detached
          envelope.with(freshness: envelope.freshness.with(fetching: true))
        when Textus::Domain::Outcome::Failed
          envelope.with(
            freshness: envelope.freshness.with(fetch_error: outcome.error.message),
          )
        end
      end
    end
  end
end
