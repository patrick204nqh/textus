module Textus
  class Manifest
    module Schema
      ROOT_KEYS    = %w[version zones entries rules].freeze
      ZONE_KEYS    = %w[name write_policy read_policy].freeze
      ENTRY_KEYS   = %w[
        key path zone schema owner nested format
        compute template publish_to publish_each
        intake events inject_intro index_filename
      ].freeze
      COMPUTE_KEYS = %w[kind select pluck sort_by limit transform command sources].freeze
      INTAKE_KEYS  = %w[handler config].freeze
      RULE_KEYS    = %w[match refresh intake_handler_allowlist promotion retention].freeze
      REFRESH_KEYS = %w[ttl on_stale sync_budget_ms].freeze
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
          walk(r["refresh"], REFRESH_KEYS, "#{path}.refresh") if r["refresh"].is_a?(Hash)
          walk(r["promotion"], PROMOTION_KEYS, "#{path}.promotion") if r["promotion"].is_a?(Hash)
        end
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
