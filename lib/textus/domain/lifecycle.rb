require "time"

module Textus
  module Domain
    # Unified lifecycle reporter (ADR 0079): which entries are past their ttl,
    # and the on_expire action that applies. Replaces both Staleness::IntakeCheck
    # and Retention. Age basis: _meta.last_fetched_at (intake) when present, else
    # file mtime (stored). `self.verdict` is the pure per-entry decision that BOTH
    # this reporter and `Read::Get` (Plan 2) call, so the basis logic lives once.
    class Lifecycle
      # Pure: is the entry past its ttl? -> [expired(bool), reason(String|nil)].
      def self.verdict(policy:, last_fetched_at:, mtime:, now:)
        ttl = policy.ttl_seconds
        return [false, nil] if ttl.nil?

        basis = parse_time(last_fetched_at) || mtime
        return [true, "never recorded"] if basis.nil?

        age = (now - basis).to_i
        age > ttl ? [true, "ttl exceeded (age=#{age}s, ttl=#{ttl}s)"] : [false, nil]
      end

      def self.parse_time(str)
        return nil if str.nil?

        Time.parse(str.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def initialize(manifest:, file_stat:, clock:)
        @manifest  = manifest
        @file_stat = file_stat
        @clock     = clock
      end

      def call(prefix: nil, zone: nil)
        @manifest.data.entries
                 .select { |m| entry_matches?(m, prefix: prefix, zone: zone) }
                 .flat_map { |m| rows_for(m) }
      end

      private

      def entry_matches?(mentry, prefix:, zone:)
        return false if zone && mentry.zone != zone
        if prefix && !Textus::Key::Matching.matches_prefix?(
          mentry.key, prefix, nested: mentry.is_a?(Textus::Manifest::Entry::Nested)
        )
          return false
        end

        true
      end

      def rows_for(mentry)
        policy = @manifest.rules.for(mentry.key).lifecycle
        return [] if policy.nil?

        @manifest.resolver.enumerate(prefix: mentry.key).filter_map do |row|
          path = row[:path]
          next unless @file_stat.exists?(path)

          expired, _reason = self.class.verdict(
            policy: policy,
            last_fetched_at: last_fetched_at_of(mentry, path),
            mtime: @file_stat.mtime(path),
            now: @clock.now,
          )
          next unless expired

          {
            "key" => row[:key], "path" => path,
            "action" => policy.on_expire.to_s, "expired" => true
          }
        end
      end

      # Reads _meta.last_fetched_at from the on-disk envelope (intake basis).
      def last_fetched_at_of(mentry, path)
        Entry.for_format(mentry.format).parse(@file_stat.read(path), path: path)["_meta"]["last_fetched_at"]
      rescue StandardError
        nil
      end
    end
  end
end
