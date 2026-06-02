module Textus
  module Read
    # Composes pure `Read::GetEntry` with the fetch orchestrator: runs GetEntry
    # to obtain the envelope and freshness verdict, then if the verdict
    # is stale and the rule's `on_stale` policy demands action, hands
    # off to the orchestrator. Use for interactive reads where the
    # caller wants the freshest obtainable envelope.
    #
    # Pure reads (build, projection, schema tooling) should use
    # `Read::GetEntry` directly; it has no orchestrator dependency.
    class Get
      extend Textus::Contract::DSL

      verb     :get
      summary  "Read one entry, fetching on stale per the entry's fetch rule " \
               "(degrades to a pure read when the key has no fetch rule). " \
               "Returns the envelope (uid, etag, _meta, body, freshness)."
      surfaces :cli, :ruby, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key to read, e.g. 'knowledge.project'"
      response(&:to_h_for_wire)

      def initialize(container:, call:, get: nil, orchestrator: nil)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @get          = get || Read::GetEntry.new(container: container, call: call)
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
