require "time"

module Textus
  module Read
    # Per-entry freshness report. Walks every entry declared in the manifest,
    # consults `rules_for(key)` for a fetch rule, and reports the
    # current status. Status is one of :fresh, :stale, :never_fetched, or
    # :no_policy.
    class Freshness
      extend Textus::Contract::DSL

      verb     :freshness
      summary  "Report the fetch-freshness status of every entry with a fetch policy."
      surfaces :cli, :ruby
      cli      "freshness"
      arg :prefix, String, required: false, description: "filter to keys with this prefix"
      arg :zone,   String, required: false, description: "filter to entries in this zone"

      def initialize(container:, call:, evaluator: Textus::Domain::Freshness::Evaluator)
        @container  = container
        @call       = call
        @manifest   = container.manifest
        @file_store = container.file_store
        @evaluator  = evaluator
        @cache      = {}
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
        set = @manifest.rules.for(mentry.key)
        fetch = set.fetch
        envelope = safe_get(mentry.key)
        last = envelope&.meta&.dig("last_fetched_at")

        return base_row(mentry, last).merge(status: :no_policy) if fetch.nil?

        fp = fetch.to_freshness_policy
        cache_key = [mentry.key, last]
        verdict = (@cache[cache_key] ||= @evaluator.call(fp, envelope, now: @call.now))
        status = if verdict.fresh? then :fresh
                 elsif last.nil?   then :never_fetched
                 else                   :stale
                 end

        base_row(mentry, last).merge(
          ttl_seconds: fp.ttl_seconds,
          on_stale: fp.on_stale,
          status: status,
          next_due_at: next_due(last, fp.ttl_seconds),
        )
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
