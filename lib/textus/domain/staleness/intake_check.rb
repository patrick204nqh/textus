require "time"

module Textus
  module Domain
    class Staleness
      # Reports TTL-exceeded staleness for intake-handler entries. Returns an
      # Array of row hashes (possibly empty) per entry.
      class IntakeCheck
        def initialize(manifest:, file_stat:, clock:)
          @manifest  = manifest
          @file_stat = file_stat
          @clock     = clock
        end

        def rows_for(mentry)
          return [] unless mentry.is_a?(Textus::Manifest::Entry::Intake)

          ttl = @manifest.rules.for(mentry.key).refresh&.ttl_seconds
          return [] unless ttl

          path = Textus::Key::Path.resolve(@manifest.data, mentry)
          reason = ttl_reason(mentry, path, ttl)
          reason ? [row(mentry, path, reason)] : []
        end

        private

        def ttl_reason(mentry, path, ttl)
          return "never refreshed" unless @file_stat.exists?(path)

          last_str = last_refreshed_of(mentry, path)
          return "never refreshed (no last_refreshed_at)" if last_str.nil?

          last = parse_time(last_str)
          "ttl exceeded (#{ttl}s)" if last.nil? || (@clock.now - last) > ttl
        end

        def last_refreshed_of(mentry, path)
          Entry.for_format(mentry.format).parse(@file_stat.read(path), path: path)["_meta"]["last_refreshed_at"]
        end

        def parse_time(str)
          Time.parse(str.to_s)
        rescue StandardError
          nil
        end

        def row(mentry, path, reason)
          { "key" => mentry.key, "path" => path, "handler" => mentry.handler, "reason" => reason }
        end
      end
    end
  end
end
