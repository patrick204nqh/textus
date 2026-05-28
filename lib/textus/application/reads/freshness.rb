require "time"

module Textus
  module Application
    module Reads
      # Per-entry freshness report. Walks every entry declared in the manifest,
      # consults `rules_for(key)` for a refresh rule, and reports the
      # current status. Status is one of :fresh, :stale, :never_refreshed, or
      # :no_policy.
      module Freshness
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(ctx: ctx, caps: caps).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, evaluator: Textus::Domain::Freshness::Evaluator)
            @ctx        = ctx
            @manifest   = caps.manifest
            @file_store = caps.file_store
            @evaluator  = evaluator
            @cache      = {}
          end

          # Returns the soonest `next_due_at` across all entries with a refresh
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
            refresh = set.refresh
            envelope = safe_get(mentry.key)
            last = envelope&.meta&.dig("last_refreshed_at")

            return base_row(mentry, last).merge(status: :no_policy) if refresh.nil?

            fp = refresh.to_freshness_policy
            cache_key = [mentry.key, last]
            verdict = (@cache[cache_key] ||= @evaluator.call(fp, envelope, now: @ctx.now))
            status = if verdict.fresh? then :fresh
                     elsif last.nil?   then :never_refreshed
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
              last_refreshed_at: last,
              age_seconds: last ? (@ctx.now - Time.parse(last)).to_i : nil,
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
  end
end

Textus::Application::UseCase.register(:freshness, Textus::Application::Reads::Freshness, caps: :read)
