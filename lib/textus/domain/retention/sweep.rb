require "time"

module Textus
  module Domain
    module Retention
      # Retention sweep reporter (ADR 0093/0099). Which entries are past their
      # `retention:` ttl and the destructive action that applies. Age basis: file
      # mtime. Only drop/archive. Renamed off the Domain::Retention vs
      # Domain::Policy::Retention collision (ADR 0099).
      class Sweep
        def self.expired?(ttl_seconds:, mtime:, now:)
          return false if ttl_seconds.nil? || mtime.nil?

          (now - mtime).to_i > ttl_seconds
        end

        def initialize(manifest:, file_stat:, clock:)
          @manifest = manifest
          @file_stat = file_stat
          @clock = clock
        end

        def call(prefix: nil, zone: nil)
          @manifest.data.entries
                   .select { |m| matches?(m, prefix: prefix, zone: zone) }
                   .flat_map { |m| rows_for(m) }
        end

        private

        def matches?(mentry, prefix:, zone:)
          return false if zone && mentry.zone != zone
          return false if prefix && !Textus::Key::Matching.matches_prefix?(
            mentry.key, prefix, nested: mentry.is_a?(Textus::Manifest::Entry::Nested)
          )

          true
        end

        def rows_for(mentry)
          policy = @manifest.rules.for(mentry.key).retention
          return [] if policy.nil?

          @manifest.resolver.enumerate(prefix: mentry.key).filter_map do |row|
            path = row[:path]
            next unless @file_stat.exists?(path)
            next unless self.class.expired?(
              ttl_seconds: policy.ttl_seconds, mtime: @file_stat.mtime(path), now: @clock.now,
            )

            { "key" => row[:key], "path" => path, "action" => policy.action.to_s }
          end
        end
      end
    end
  end
end
