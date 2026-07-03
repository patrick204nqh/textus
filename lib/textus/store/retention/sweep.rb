require "time"

module Textus
  class Store
    module Retention
      class Sweep
        def self.expired?(ttl_seconds:, mtime:, now:)
          return false if ttl_seconds.nil? || mtime.nil?

          (now - mtime).to_i > ttl_seconds
        end

        def initialize(manifest:, workflows:, file_stat:, clock:)
          @manifest  = manifest
          @workflows = workflows
          @file_stat = file_stat
          @clock     = clock
        end

        def call(prefix: nil, lane: nil)
          @manifest.data.entries
                   .select { |m| matches?(m, prefix: prefix, lane: lane) }
                   .flat_map { |m| rows_for(m) }
        end

        private

        def matches?(mentry, prefix:, lane:)
          return false if lane && mentry.lane != lane
          return false if prefix && !Textus::Key::Matching.matches_prefix?(
            mentry.key, prefix, nested: mentry.is_a?(Textus::Manifest::Entry::Nested)
          )

          true
        end

        def rows_for(mentry)
          ttl_seconds, action = lifecycle_for(mentry.key)
          return [] if ttl_seconds.nil?

          @manifest.resolver.enumerate(prefix: mentry.key).filter_map do |row|
            path = row[:path]
            next unless @file_stat.exists?(path)
            next unless self.class.expired?(
              ttl_seconds: ttl_seconds, mtime: @file_stat.mtime(path), now: @clock.now,
            )

            { "key" => row[:key], "path" => path, "action" => action }
          end
        end

        def lifecycle_for(key)
          wf = @workflows.find { |d| d.match?(key) }
          return [wf.ttl, wf.on_expire.to_s] if wf&.ttl

          entry = @manifest.data.entries.find { |e| e.key == key || key.start_with?("#{e.key}.") }
          lane_ttl = entry ? Textus::Protocol::V4::LANES.dig(entry.lane, :retention_ttl) : nil
          return [lane_ttl, "archive"] if lane_ttl

          [nil, nil]
        end
      end
    end
  end
end
