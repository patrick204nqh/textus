module Textus
  class Manifest
    module Schema
      ROOT_KEYS    = %w[version zones entries rules].freeze
      ZONE_KEYS    = %w[name write_policy read_policy].freeze
      ENTRY_KEYS   = %w[
        key path zone kind schema owner nested format
        compute template publish_to publish_each
        intake events inject_intro index_filename
      ].freeze
      COMPUTE_KEYS = %w[kind select pluck sort_by limit transform command sources].freeze
      INTAKE_KEYS  = %w[handler config].freeze
      RULE_KEYS    = %w[match refresh intake_handler_allowlist promotion retention].freeze
      REFRESH_KEYS = %w[ttl on_stale sync_budget_ms fetch_timeout_seconds].freeze
      FETCH_TIMEOUT_SECONDS_CEILING = 3600
      PROMOTION_KEYS = %w[requires].freeze

      def self.validate!(raw)
        raise BadManifest.new("manifest must be a hash") unless raw.is_a?(Hash)

        walk(raw, ROOT_KEYS, "$")
        Array(raw["zones"]).each_with_index do |z, i|
          walk(z, ZONE_KEYS, "$.zones[#{i}]")
        end
        Array(raw["entries"]).each_with_index do |e, i|
          path = "$.entries[#{i}]"
          walk(e, ENTRY_KEYS, path)
          walk(e["compute"], COMPUTE_KEYS, "#{path}.compute") if e["compute"].is_a?(Hash)
          walk(e["intake"], INTAKE_KEYS, "#{path}.intake") if e["intake"].is_a?(Hash)
        end
        Array(raw["rules"]).each_with_index do |r, i|
          path = "$.rules[#{i}]"
          walk(r, RULE_KEYS, path)
          if r["refresh"].is_a?(Hash)
            walk(r["refresh"], REFRESH_KEYS, "#{path}.refresh")
            validate_fetch_timeout!(r["refresh"]["fetch_timeout_seconds"], "#{path}.refresh.fetch_timeout_seconds")
          end
          walk(r["promotion"], PROMOTION_KEYS, "#{path}.promotion") if r["promotion"].is_a?(Hash)
        end
      end

      def self.validate_fetch_timeout!(value, path)
        return if value.nil?
        return if value.is_a?(Integer) && value.positive? && value <= FETCH_TIMEOUT_SECONDS_CEILING

        raise BadManifest.new(
          "fetch_timeout_seconds at '#{path}' must be a positive integer ≤ #{FETCH_TIMEOUT_SECONDS_CEILING} (got #{value.inspect})",
        )
      end

      def self.walk(hash, allowed, path)
        return unless hash.is_a?(Hash)

        hash.each_key do |k|
          next if allowed.include?(k)

          raise BadManifest.new("unknown key '#{k}' at '#{path}'")
        end
      end
    end
  end
end
