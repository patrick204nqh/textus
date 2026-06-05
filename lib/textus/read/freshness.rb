require "time"

module Textus
  module Read
    # Per-entry lifecycle scan (ADR 0079, 0085). Walks every entry declared in
    # the manifest, consults `rules.for(key)` for a `lifecycle:` policy, and
    # reports the unified verdict. Status is one of :fresh, :expired, or
    # :no_policy; the row also carries the policy's :action (on_expire).
    #
    # ADR 0085 removed the public `freshness` verb: there is no `:cli`/`:mcp`
    # surface. This is now a Ruby-only internal scan (empty `surfaces`, the
    # honest home reserved by ADR 0073) consumed by `pulse` (which derives
    # `stale` + `next_due_at` from it) and the hook `Context`. Humans drill
    # into per-entry lifecycle detail via `get` (last_fetched_at) + `rule_explain`
    # (the ttl / on_expire policy) instead of a dedicated verb.
    class Freshness
      extend Textus::Contract::DSL

      verb     :freshness
      summary  "Internal per-entry lifecycle scan (status, age, ttl, on_expire); backs pulse + hook context. No public surface (ADR 0085)."
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
        policy = lifecycle_for(mentry.key)
        envelope = safe_get(mentry.key)
        last = envelope&.meta&.dig("last_fetched_at")

        return base_row(mentry, last).merge(status: :no_policy) if policy.nil?

        expired, reason = Textus::Domain::Lifecycle.verdict(
          policy: policy,
          last_fetched_at: last,
          mtime: mtime_for(mentry.key),
          now: @call.now,
        )
        base_row(mentry, last).merge(
          ttl_seconds: policy.ttl_seconds,
          action: policy.on_expire,
          status: expired ? :expired : :fresh,
          reason: reason,
          next_due_at: next_due(last, policy.ttl_seconds),
        )
      end

      def lifecycle_for(key)
        @manifest.rules.for(key).upkeep&.lifecycle
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

      def next_due(last, ttl)
        return nil if last.nil? || ttl.nil?

        (Time.parse(last) + ttl).utc.iso8601
      end
    end
  end
end
