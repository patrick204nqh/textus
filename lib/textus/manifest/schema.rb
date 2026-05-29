module Textus
  class Manifest
    module Schema
      ROOT_KEYS    = %w[version roles zones entries rules audit].freeze
      ROLE_KEYS    = %w[name kind].freeze
      ROLE_KINDS   = %w[accept_authority generator proposer runner].freeze
      ZONE_KEYS    = %w[name kind write_policy read_policy].freeze
      ZONE_KINDS   = %w[origin quarantine queue derived].freeze
      KIND_REQUIRES_ROLE_KIND = {
        "derived" => "generator",
        "queue" => "proposer",
        "quarantine" => "runner",
      }.freeze
      ENTRY_KEYS = %w[
        key path zone kind schema owner nested format
        compute template publish_to publish_each
        intake events inject_boot index_filename
      ].freeze
      COMPUTE_KEYS = %w[kind select pluck sort_by limit transform command sources].freeze
      INTAKE_KEYS  = %w[handler config].freeze
      RULE_KEYS    = %w[match refresh intake_handler_allowlist promotion retention].freeze
      REFRESH_KEYS = %w[ttl on_stale sync_budget_ms fetch_timeout_seconds].freeze
      FETCH_TIMEOUT_SECONDS_CEILING = 3600
      PROMOTION_KEYS  = %w[requires].freeze
      RETENTION_KEYS  = %w[expire_after archive_after].freeze
      AUDIT_KEYS = %w[max_size keep].freeze

      def self.validate!(raw)
        raise BadManifest.new("manifest must be a hash") unless raw.is_a?(Hash)

        walk(raw, ROOT_KEYS, "$")
        validate_roles!(raw["roles"])
        validate_zones!(raw["zones"])
        validate_entries!(raw["entries"])
        validate_rules!(raw["rules"])
        walk(raw["audit"], AUDIT_KEYS, "$.audit") if raw["audit"].is_a?(Hash)
        validate_zone_writers_declared!(raw)
        validate_single_queue!(raw)
        validate_zone_kind_consistency!(raw)
      end

      def self.validate_zones!(zones)
        Array(zones).each_with_index do |z, i|
          walk(z, ZONE_KEYS, "$.zones[#{i}]")
          if z["kind"].nil?
            raise BadManifest.new("zone '#{z["name"]}' at '$.zones[#{i}]' must declare a kind (one of: #{ZONE_KINDS.join(", ")})")
          end
          next if ZONE_KINDS.include?(z["kind"])

          raise BadManifest.new(
            "unknown zone kind '#{z["kind"]}' at '$.zones[#{i}]' (known: #{ZONE_KINDS.join(", ")})",
          )
        end
      end

      def self.validate_entries!(entries)
        Array(entries).each_with_index do |e, i|
          path = "$.entries[#{i}]"
          walk(e, ENTRY_KEYS, path)
          walk(e["compute"], COMPUTE_KEYS, "#{path}.compute") if e["compute"].is_a?(Hash)
          walk(e["intake"], INTAKE_KEYS, "#{path}.intake") if e["intake"].is_a?(Hash)
        end
      end

      def self.validate_rules!(rules)
        Array(rules).each_with_index do |r, i|
          path = "$.rules[#{i}]"
          walk(r, RULE_KEYS, path)
          if r["refresh"].is_a?(Hash)
            walk(r["refresh"], REFRESH_KEYS, "#{path}.refresh")
            validate_fetch_timeout!(r["refresh"]["fetch_timeout_seconds"], "#{path}.refresh.fetch_timeout_seconds")
          end
          walk(r["promotion"], PROMOTION_KEYS, "#{path}.promotion") if r["promotion"].is_a?(Hash)
          walk(r["retention"], RETENTION_KEYS, "#{path}.retention") if r["retention"].is_a?(Hash)
        end
      end

      def self.validate_zone_writers_declared!(raw)
        return if raw["roles"].nil? # default mapping is permissive

        declared = Array(raw["roles"]).map { |r| r["name"] }.compact.to_set
        Array(raw["zones"]).each do |z|
          Array(z["write_policy"]).each_with_index do |w, j|
            next if declared.include?(w)

            raise BadManifest.new(
              "zone '#{z["name"]}' write_policy[#{j}] references undeclared role '#{w}' " \
              "(declared roles: #{declared.to_a.join(", ")})",
            )
          end
        end
      end

      def self.validate_roles!(roles)
        return if roles.nil?
        raise BadManifest.new("roles: must be a list") unless roles.is_a?(Array)

        accept_authority_count = 0
        roles.each_with_index do |r, i|
          path = "$.roles[#{i}]"
          walk(r, ROLE_KEYS, path)
          name = r["name"] or raise BadManifest.new("role at '#{path}' missing name")
          kind = r["kind"] or raise BadManifest.new("role '#{name}' at '#{path}' missing kind")
          unless ROLE_KINDS.include?(kind)
            raise BadManifest.new("unknown role kind '#{kind}' at '#{path}' (known: #{ROLE_KINDS.join(", ")})")
          end

          accept_authority_count += 1 if kind == "accept_authority"
        end
        return unless accept_authority_count > 1

        raise BadManifest.new(
          "manifest declares #{accept_authority_count} accept_authority roles; " \
          "at most one accept_authority role is allowed",
        )
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

      def self.validate_single_queue!(raw)
        queues = Array(raw["zones"]).select { |z| z["kind"] == "queue" }.map { |z| z["name"] }
        return if queues.size <= 1

        raise BadManifest.new(
          "at most one zone may declare kind: queue (found: #{queues.join(", ")})",
        )
      end

      def self.validate_zone_kind_consistency!(raw)
        mapping = role_kind_mapping(raw)
        Array(raw["zones"]).each do |z|
          required = KIND_REQUIRES_ROLE_KIND[z["kind"]] or next
          writers  = Array(z["write_policy"])
          next if writers.any? { |w| mapping[w] == required }

          raise BadManifest.new(
            "zone '#{z["name"]}' declares kind: #{z["kind"]} but no writer is a #{required} " \
            "(writers: #{writers.join(", ")})",
          )
        end
      end

      # name => kind string, honouring an explicit roles: block or the default mapping.
      def self.role_kind_mapping(raw)
        if raw["roles"].nil?
          RoleKinds::DEFAULT_MAPPING.transform_values(&:to_s)
        else
          Array(raw["roles"]).to_h { |r| [r["name"], r["kind"]] }
        end
      end
    end
  end
end
