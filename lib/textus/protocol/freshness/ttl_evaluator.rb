# frozen_string_literal: true

module Textus
  module Protocol
    module Freshness
      class TtlEvaluator
        def initialize(manifest:, file_stat:, clock:)
          @manifest  = manifest
          @file_stat = file_stat
          @clock     = clock
        end

        def verdict(mentry)
          ttl = lane_ttl(mentry.lane)
          return fresh if ttl.nil?

          stale = age_stale?(file_basis(mentry), ttl)
          Verdict.build(stale: stale, reason: stale ? "ttl exceeded" : nil, fetching: false)
        end

        def stale_keys(prefix: nil, lane: nil)
          @manifest.data.entries.select { |m| due?(m, prefix: prefix, lane: lane) }.map(&:key)
        end

        private

        def fresh = Verdict.build(stale: false, reason: nil, fetching: false)

        def file_basis(mentry)
          path = @manifest.resolver.resolve(mentry.key).path
          return nil unless @file_stat.exists?(path)

          @file_stat.mtime(path)
        end

        def lane_ttl(lane)
          Textus::Protocol::V4::LANES.dig(lane, :retention_ttl)
        end

        def due?(mentry, prefix:, lane:)
          return false if lane && mentry.lane != lane
          return false if prefix && !mentry.key.start_with?(prefix)

          ttl = lane_ttl(mentry.lane)
          return false if ttl.nil?

          path = @manifest.resolver.resolve(mentry.key).path
          return true unless @file_stat.exists?(path)

          age_stale?(file_basis(mentry), ttl)
        end

        def age_stale?(basis, ttl)
          return true if basis.nil?

          (@clock.now - basis).to_i > ttl
        end
      end
    end
  end
end
