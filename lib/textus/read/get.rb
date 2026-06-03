module Textus
  module Read
    # The one read path. `fetch:` controls behavior:
    #   fetch: false (default) — pure read: the on-disk envelope annotated with
    #     a freshness verdict. NEVER builds the orchestrator (no threads/forks/
    #     locks/events). This is the safe default for direct (in-process)
    #     callers — accept/reject/publish, materializer, uid, validate_all/
    #     validator, schema tooling, and the hook context — that must read
    #     persisted truth without triggering a fetch.
    #   fetch: true — read-through: after a stale verdict, hands off to the
    #     fetch orchestrator per the entry's fetch rule (degrades to the pure
    #     result when the key has no rule).
    #
    # The public `get` verb is read-through because the contract declares
    # `arg :fetch, default: true`, injected on every verb surface (RoleScope +
    # MCP map_args, ADR 0062 amendment). Direct construction bypasses that
    # injection and so gets the safe `fetch: false` method default.
    class Get
      extend Textus::Contract::DSL

      verb     :get
      summary  "Read one entry. Read-through by default — fetches on stale per " \
               "the entry's fetch rule, degrading to a pure read when the key " \
               "has no rule. Pass fetch:false for a guaranteed pure on-disk " \
               "read. Returns the envelope (uid, etag, _meta, body, freshness)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key to read, e.g. 'knowledge.project'"
      arg :fetch, :boolean, default: true,
                            description: "read-through (fetch on stale per the " \
                                         "entry's fetch rule) when true, the default; " \
                                         "false returns the on-disk envelope without ever fetching"
      view { |v, _i| v.to_h_for_wire }

      def initialize(container:, call:, evaluator: Textus::Domain::Freshness::Evaluator, orchestrator: nil)
        @container  = container
        @call       = call
        @manifest   = container.manifest
        @file_store = container.file_store
        @evaluator  = evaluator
        @orchestrator = orchestrator # nil → built lazily on first fetch only
      end

      def call(key, fetch: false)
        envelope = annotated_envelope(key)
        return envelope if envelope.nil?
        return envelope unless fetch && envelope.freshness&.stale

        fetch_policy = fetch_policy_for(key)
        return envelope if fetch_policy.nil?

        policy  = fetch_policy.to_freshness_policy
        verdict = Textus::Domain::Freshness::Verdict.stale(envelope.freshness.reason)
        outcome = orchestrator.execute(policy.decide(verdict), key: key)
        resolve(outcome, envelope)
      end

      # Strict variant: raises UnknownKey when the entry is missing.
      # Used by consumers (e.g. uid, Validator) that distinguish absence.
      def get(key, fetch: false)
        call(key, fetch: fetch) ||
          raise(UnknownKey.new(key, suggestions: @manifest.resolver.suggestions_for(key)))
      end

      private

      # Pure read + freshness verdict; no orchestrator dependency.
      def annotated_envelope(key)
        envelope = read_raw_envelope(key)
        return nil if envelope.nil?

        fetch_policy = fetch_policy_for(key)
        return annotate_fresh(envelope) if fetch_policy.nil?

        policy  = fetch_policy.to_freshness_policy
        verdict = @evaluator.call(policy, envelope, now: @call.now)
        envelope.with(freshness: Textus::Domain::Freshness.build(
          stale: verdict.stale?, reason: verdict.reason, fetching: false,
        ))
      end

      def fetch_policy_for(key)
        @manifest.rules.for(key).fetch
      end

      def resolve(outcome, envelope)
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
          envelope.with(freshness: envelope.freshness.with(fetch_error: outcome.error.message))
        else raise "unexpected fetch outcome: #{outcome.class}"
        end
      end

      def read_raw_envelope(key)
        res = @manifest.resolver.resolve(key)
        mentry = res.entry
        path = res.path
        return nil unless @file_store.exists?(path)

        raw = @file_store.read(path)
        parsed = Entry.for_format(mentry.format).parse(raw, path: path)
        Textus::Envelope.build(
          key: key, mentry: mentry, path: path,
          meta: parsed["_meta"], body: parsed["body"],
          etag: Etag.for_bytes(raw), content: parsed["content"]
        )
      end

      def annotate_fresh(envelope)
        envelope.with(freshness: Textus::Domain::Freshness.build(
          stale: false, reason: nil, fetching: false,
        ))
      end

      def orchestrator
        @orchestrator ||= build_orchestrator
      end

      def build_orchestrator
        worker = Textus::Write::FetchWorker.new(container: @container, call: @call)
        Textus::Write::FetchOrchestrator.new(
          worker: worker, store_root: @container.root, events: @container.events,
          hook_context: hook_context
        )
      end

      def hook_context
        @hook_context ||= Textus::Hooks::Context.for(container: @container, call: @call)
      end
    end
  end
end
