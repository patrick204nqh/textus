module Textus
  module Read
    # The one read path. `fetch:` controls behavior:
    #   fetch: false (default) — pure read: the on-disk envelope annotated with
    #     a lifecycle freshness verdict. NEVER builds the orchestrator and NEVER
    #     mutates. Safe for direct callers (accept/reject/publish, materializer,
    #     uid, validators, hooks).
    #   fetch: true — read-through: after a stale verdict on a `refresh` policy,
    #     hands off to the fetch orchestrator. A read NEVER performs a
    #     destructive action (drop/archive) — those belong to the `reconcile` sweep
    #     (ADR 0079).
    #
    # Lifecycle policy comes from the unified `lifecycle:` rule slot (ADR 0079).
    class Get
      extend Textus::Contract::DSL

      verb     :get
      summary  "Read one entry. Read-through by default — refreshes on stale per " \
               "the entry's lifecycle rule (on_expire: refresh), degrading to a " \
               "pure read when the key has no rule. Pass fetch:false for a " \
               "guaranteed pure on-disk read. Returns the envelope (uid, etag, " \
               "_meta, body, freshness)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key to read, e.g. 'knowledge.project'"
      arg :fetch, :boolean, default: true,
                            description: "read-through (refresh on stale per the " \
                                         "entry's lifecycle rule) when true, the default; " \
                                         "false returns the on-disk envelope without ever fetching"
      view { |v, _i| v.to_h_for_wire }

      def initialize(container:, call:, orchestrator: nil, file_stat: Textus::Ports::Storage::FileStat.new)
        @container  = container
        @call       = call
        @manifest   = container.manifest
        @file_store = container.file_store
        @file_stat  = file_stat
        @orchestrator = orchestrator # nil → built lazily on first fetch only
      end

      def call(key, fetch: false)
        envelope = annotated_envelope(key)
        return envelope if envelope.nil?
        return envelope unless fetch && envelope.freshness&.stale

        policy = lifecycle_for(key)
        return envelope unless policy&.on_expire == :refresh # only refresh acts on a read

        verdict = Textus::Domain::Freshness::Verdict.stale(envelope.freshness.reason)
        outcome = orchestrator.execute(refresh_policy(policy).decide(verdict), key: key)
        resolve(outcome, envelope)
      end

      # Strict variant: raises UnknownKey when the entry is missing.
      # Used by consumers (e.g. uid, Validator) that distinguish absence.
      def get(key, fetch: false)
        call(key, fetch: fetch) ||
          raise(UnknownKey.new(key, suggestions: @manifest.resolver.suggestions_for(key)))
      end

      private

      # Pure read + unified lifecycle verdict; no orchestrator dependency.
      def annotated_envelope(key)
        envelope = read_raw_envelope(key)
        return nil if envelope.nil?

        policy = lifecycle_for(key)
        return annotate_fresh(envelope) if policy.nil?

        expired, reason = Textus::Domain::Lifecycle.verdict(
          policy: policy,
          last_fetched_at: envelope.meta&.dig("last_fetched_at"),
          mtime: mtime_for(key),
          now: @call.now,
        )
        envelope.with(freshness: Textus::Domain::Freshness.build(
          stale: expired, reason: reason, fetching: false,
        ))
      end

      def lifecycle_for(key)
        @manifest.rules.for(key).lifecycle
      end

      def refresh_policy(policy)
        Textus::Domain::Freshness::Policy.new(
          ttl_seconds: policy.ttl_seconds,
          on_stale: policy.budget_ms ? :timed_sync : :sync,
          sync_budget_ms: policy.budget_ms,
        )
      end

      def mtime_for(key)
        path = @manifest.resolver.resolve(key).path
        @file_stat.exists?(path) ? @file_stat.mtime(path) : nil
      rescue Textus::Error
        nil
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
