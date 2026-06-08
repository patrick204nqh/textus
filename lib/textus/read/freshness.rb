require "time"

module Textus
  module Read
    # Per-entry staleness scan (ADR 0079, 0085, 0093). Walks every entry declared
    # in the manifest and reports a staleness verdict sourced from the two new
    # policy slots (ADR 0093):
    #   - intake entries: `entry.source.ttl_seconds` is the re-pull cadence;
    #     basis = `_meta.last_fetched_at` (else file mtime). Past ttl ⇒ :expired.
    #   - entries matched by a `retention:` rule: `retention.ttl_seconds` is the
    #     GC age; basis = file mtime. Past ttl ⇒ :expired (:action = drop/archive).
    # Intake cadence wins when both apply (freshness is content currency; GC dueness
    # shows via `drain --dry-run`).
    # Status is one of :fresh, :expired, or :no_policy; the row also carries
    # :action (:refresh for intake, :drop/:archive for retention).
    #
    # ADR 0085 removed the public `freshness` verb: there is no `:cli`/`:mcp`
    # surface. This is now a Ruby-only internal scan consumed by `pulse` (which
    # derives `stale` + `next_due_at` from it) and the hook `Context`. Humans drill
    # into per-entry staleness detail via `get` (last_fetched_at) + `rule_explain`
    # (the ttl / action policy) instead of a dedicated verb.
    class Freshness
      extend Textus::Contract::DSL

      verb     :freshness
      summary  "Internal per-entry lifecycle scan (status, age, ttl, action); backs pulse + hook context. No public surface (ADR 0085)."
      arg :prefix, String, required: false, description: "filter to keys with this prefix"
      arg :zone,   String, required: false, description: "filter to entries in this zone"

      def initialize(container:, call:)
        @container  = container
        @call       = call
        @manifest   = container.manifest
        @file_store = container.file_store
      end

      # Returns the soonest `next_due_at` across all entries with a fetch
      # policy, as an ISO-8601 string, or nil if none.
      def soonest_due(prefix: nil, zone: nil)
        times = call(prefix: prefix, zone: zone)
                .map { |r| r[:next_due_at] }
                .compact
                .map { |t| Time.parse(t) }
        return nil if times.empty?

        times.min.utc.iso8601
      end

      def call(prefix: nil, zone: nil)
        rows = []
        @manifest.data.entries.each do |mentry|
          next if prefix && !mentry.key.start_with?(prefix)
          next if zone && mentry.zone != zone

          rows << row_for(mentry)
        end
        rows
      end

      private

      def row_for(mentry)
        envelope = safe_get(mentry.key)
        last = envelope&.meta&.dig("last_fetched_at")
        ttl, action = policy_for(mentry)
        return base_row(mentry, last).merge(status: :no_policy) if ttl.nil?

        basis = basis_for(mentry)
        expired = expired?(mentry, basis, ttl)
        base_row(mentry, last).merge(
          ttl_seconds: ttl,
          action: action,
          status: expired ? :expired : :fresh,
          next_due_at: basis.nil? ? nil : (basis + ttl).utc.iso8601,
        )
      end

      # ADR 0093: staleness comes from the intake re-pull cadence (source.ttl)
      # or a retention GC rule (retention.ttl). Intake cadence wins when an entry
      # has both (freshness is about content currency; GC dueness still shows via
      # `drain --dry-run`). Returns [ttl_seconds, action] or [nil, nil].
      def policy_for(mentry)
        if mentry.intake?
          ttl = mentry.source.ttl_seconds
          return [ttl, :refresh] unless ttl.nil?
        end
        ret = @manifest.rules.for(mentry.key).retention
        return [ret.ttl_seconds, ret.action] unless ret.nil?

        [nil, nil]
      end

      # Intake currency basis comes from the evaluator (single definition);
      # retention dueness is keyed off file mtime.
      def basis_for(mentry)
        return evaluator.intake_basis(mentry) if mentry.intake? && mentry.source.ttl_seconds

        mtime_for(mentry.key)
      end

      def expired?(mentry, basis, ttl)
        if mentry.intake? && mentry.source.ttl_seconds
          evaluator.verdict(mentry).stale
        else
          # Preserve pre-0099 pulse semantics: a never-recorded retention entry
          # (no file => nil basis) is past due. Retention::Sweep.expired? alone
          # returns false on nil mtime (it runs post-exists? in the sweep).
          basis.nil? || Textus::Domain::Retention::Sweep.expired?(ttl_seconds: ttl, mtime: basis, now: @call.now)
        end
      end

      def evaluator
        @evaluator ||= Textus::Domain::Freshness::Evaluator.new(
          manifest: @manifest, file_stat: Textus::Ports::Storage::FileStat.new, clock: @call,
        )
      end

      def mtime_for(key)
        path = @manifest.resolver.resolve(key).path
        @file_store.exists?(path) ? Textus::Ports::Storage::FileStat.new.mtime(path) : nil
      rescue Textus::Error
        nil
      end

      def base_row(mentry, last)
        {
          key: mentry.key,
          zone: mentry.zone,
          last_fetched_at: last,
          age_seconds: last ? (@call.now - Time.parse(last)).to_i : nil,
        }
      end

      # Returns the raw envelope or nil. Nested entries (mentry.key is a
      # prefix, not a leaf) and missing files both resolve to nil.
      def safe_get(key)
        res = @manifest.resolver.resolve(key)
        return nil unless @file_store.exists?(res.path)

        raw = @file_store.read(res.path)
        parsed = Entry.for_format(res.entry.format).parse(raw, path: res.path)
        Textus::Envelope.build(
          key: key, mentry: res.entry, path: res.path,
          meta: parsed["_meta"], body: parsed["body"],
          etag: Etag.for_bytes(raw), content: parsed["content"]
        )
      rescue Textus::Error
        nil
      end
    end
  end
end
