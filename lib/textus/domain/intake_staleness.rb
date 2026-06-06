require "time"

module Textus
  module Domain
    # Which intake entries are past their `source.ttl` re-pull cadence (ADR
    # 0093). The full-`reconcile` produce scope for intake — derived entries are
    # always re-rendered (cheap, idempotent), but intake re-pulls only when due,
    # so external sources aren't hammered every pass. Age basis:
    # _meta.last_fetched_at when present, else file mtime.
    class IntakeStaleness
      def initialize(manifest:, file_stat:, clock:)
        @manifest = manifest
        @file_stat = file_stat
        @clock = clock
      end

      def call(prefix: nil, zone: nil)
        @manifest.data.entries.select { |m| due?(m, prefix: prefix, zone: zone) }.map(&:key)
      end

      private

      def due?(mentry, prefix:, zone:)
        return false unless mentry.intake?
        return false if zone && mentry.zone != zone
        return false if prefix && !mentry.key.start_with?(prefix)

        ttl = mentry.source.ttl_seconds
        return true if ttl.nil? # no cadence declared -> always re-pull on the full pass

        path = @manifest.resolver.resolve(mentry.key).path
        return true unless @file_stat.exists?(path)

        basis = last_fetched_at(mentry, path) || @file_stat.mtime(path)
        return true if basis.nil?

        (@clock.now - basis).to_i > ttl
      end

      def last_fetched_at(mentry, path)
        meta = Entry.for_format(mentry.format).parse(@file_stat.read(path), path: path)["_meta"]
        Time.parse(meta["last_fetched_at"].to_s) if meta && meta["last_fetched_at"]
      rescue StandardError
        nil
      end
    end
  end
end
