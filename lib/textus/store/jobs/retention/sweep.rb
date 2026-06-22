require "time"

module Textus
  class Store
    module Jobs
      module Retention
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
end
