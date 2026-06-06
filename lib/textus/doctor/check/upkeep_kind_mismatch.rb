module Textus
  module Doctor
    class Check
      # ADR 0090: the `upkeep` tag must match the entry kind — the invariant that
      # makes the tagged union lossless (one tag per entry kind).
      #   - on: source_change is dependency-based and only applies to a `derived`
      #     (computed) entry.
      #   - on: stale with a destructive action (drop/archive) is age-retention,
      #     which never applies to a `derived` entry — it is a byte-equal
      #     regenerable projection, so dropping it on age is meaningless.
      class UpkeepKindMismatch < Check
        def call
          manifest.data.entries.filter_map do |mentry|
            upkeep = manifest.rules.for(mentry.key).upkeep
            next if upkeep.nil?

            if upkeep.source_change? && !mentry.derived?
              source_change_issue(mentry)
            elsif upkeep.stale? && mentry.derived? && upkeep.lifecycle.destructive?
              retention_issue(mentry, upkeep)
            end
          end
        end

        private

        def source_change_issue(mentry)
          issue(
            mentry.key,
            "on: source_change is only valid for a derived entry",
            "use on: stale (ttl/action) for a non-derived entry, or make this entry derived",
          )
        end

        def retention_issue(mentry, upkeep)
          issue(
            mentry.key,
            "on: stale action: #{upkeep.lifecycle.on_expire} (age-retention) is not valid for a derived entry",
            "a derived entry regenerates; drop the upkeep or use on: source_change",
          )
        end

        def issue(key, message, fix)
          {
            "code" => "upkeep.kind_mismatch",
            "level" => "error",
            "subject" => key,
            "message" => "entry '#{key}': #{message}",
            "fix" => fix,
          }
        end
      end
    end
  end
end
