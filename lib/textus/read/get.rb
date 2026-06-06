module Textus
  module Read
    # The one read path — a pure read (ADR 0089): the on-disk envelope annotated
    # with a lifecycle freshness verdict. It NEVER mutates and NEVER ingests.
    # Quarantine freshness is system-pushed via `reconcile` (scheduled sweep) and
    # `hook run` (event push) — a read no longer triggers ingest (the read-that-
    # writes seam ADR 0062 introduced is removed). A stale `on_expire: refresh`
    # entry stays stale until the next reconcile; its staleness is reported in the
    # `freshness` annotation (and surfaced by `pulse`).
    #
    # Lifecycle policy comes from the unified `lifecycle:` rule slot (ADR 0079).
    class Get
      extend Textus::Contract::DSL

      verb     :get
      summary  "Read one entry — a pure on-disk read annotated with a freshness " \
               "verdict; never ingests (quarantine freshness is reconcile + hook " \
               "only, ADR 0089). Returns the envelope (uid, etag, _meta, body, " \
               "freshness)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key to read, e.g. 'knowledge.project'"
      view { |v, _i| v.to_h_for_wire }

      def initialize(container:, call:, file_stat: Textus::Ports::Storage::FileStat.new)
        @container  = container
        @call       = call
        @manifest   = container.manifest
        @file_store = container.file_store
        @file_stat  = file_stat
      end

      def call(key)
        annotated_envelope(key)
      end

      # Strict variant: raises UnknownKey when the entry is missing.
      # Used by consumers (e.g. uid, Validator) that distinguish absence.
      def get(key)
        call(key) ||
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
        @manifest.rules.for(key).upkeep&.lifecycle
      end

      def mtime_for(key)
        path = @manifest.resolver.resolve(key).path
        @file_stat.exists?(path) ? @file_stat.mtime(path) : nil
      rescue Textus::Error
        nil
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
    end
  end
end
