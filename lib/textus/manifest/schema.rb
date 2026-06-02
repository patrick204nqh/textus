module Textus
  class Manifest
    module Schema
      ROOT_KEYS    = %w[version roles zones entries rules audit].freeze
      ROLE_KEYS    = %w[name can].freeze
      ZONE_KEYS    = %w[name kind owner desc].freeze
      # The closed coordination vocabulary (ADR 0028; completed at five in ADR
      # 0033; unified here in ADR 0034). Each lane pairs a zone-kind with the
      # single capability that authorizes originating bytes in it — a total
      # bijection. This table is the ONE source of truth; the three legacy
      # constants below are derived from it so a zone-kind and its required
      # capability cannot drift. Key order is canon-first so the unknown-kind
      # error message reads canon, workspace, quarantine, queue, derived.
      LANES = {
        "canon" => "author",
        "workspace" => "keep",
        "quarantine" => "fetch",
        "queue" => "propose",
        "derived" => "build",
      }.freeze

      ZONE_KINDS         = LANES.keys.freeze
      CAPABILITIES       = LANES.values.freeze
      KIND_REQUIRES_VERB = LANES
      ENTRY_KEYS = %w[
        key path zone kind schema owner nested format
        compute template publish_to publish_each publish_tree
        intake events inject_boot index_filename ignore tracked
      ].freeze
      COMPUTE_KEYS = %w[kind select pluck sort_by limit transform command sources].freeze
      INTAKE_KEYS  = %w[handler config].freeze
      RULE_KEYS    = %w[match fetch intake_handler_allowlist guard retention].freeze
      FETCH_KEYS = %w[ttl on_stale sync_budget_ms fetch_timeout_seconds].freeze
      FETCH_TIMEOUT_SECONDS_CEILING = 3600
      RETENTION_KEYS = %w[expire_after archive_after].freeze
      AUDIT_KEYS = %w[max_size keep].freeze

      # Syntactic shape of an `owner:` subject token (the `patrick` in
      # `human:patrick`) — the subject half of the owner-validation rule below.
      # Role supplies the archetype set (Role::NAMES); this pattern is the
      # owner-specific part, so it lives with the rule that composes them
      # (ADR 0045 D1). Acting-role *names* are gated by Role::NAMES, not a regex.
      OWNER_SUBJECT_PATTERN = /\A[a-z][a-z0-9_-]*\z/

      def self.validate!(raw)
        raise BadManifest.new("manifest must be a hash") unless raw.is_a?(Hash)

        walk(raw, ROOT_KEYS, "$")
        validate_roles!(raw["roles"])
        validate_zones!(raw["zones"])
        validate_entries!(raw["entries"])
        validate_owners!(raw["zones"], raw["entries"])
        validate_rules!(raw["rules"])
        walk(raw["audit"], AUDIT_KEYS, "$.audit") if raw["audit"].is_a?(Hash)
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
          if r["fetch"].is_a?(Hash)
            walk(r["fetch"], FETCH_KEYS, "#{path}.fetch")
            validate_fetch_timeout!(r["fetch"]["fetch_timeout_seconds"], "#{path}.fetch.fetch_timeout_seconds")
          end
          walk(r["retention"], RETENTION_KEYS, "#{path}.retention") if r["retention"].is_a?(Hash)
        end
      end

      def self.validate_roles!(roles)
        return if roles.nil?
        raise BadManifest.new("roles: must be a list") unless roles.is_a?(Array)

        roles.each_with_index do |r, i|
          path = "$.roles[#{i}]"
          walk(r, ROLE_KEYS, path)
          name = r["name"] or raise BadManifest.new("role at '#{path}' missing name")
          unless Textus::Role::NAMES.include?(name)
            raise BadManifest.new(
              "unknown role name '#{name}' at '#{path}' " \
              "(allowed: #{Textus::Role::NAMES.join(", ")})",
            )
          end
          Array(r["can"]).each do |verb|
            next if CAPABILITIES.include?(verb)

            raise BadManifest.new(
              "unknown capability '#{verb}' for role '#{name}' at '#{path}' " \
              "(known: #{CAPABILITIES.join(", ")})",
            )
          end
        end

        author_holders = roles.count { |r| Array(r["can"]).include?("author") }
        return if author_holders <= 1

        raise BadManifest.new(
          "manifest declares #{author_holders} roles with the author capability; at most one is allowed",
        )
      end

      # Owners are validated against the SAME closed archetype set as role names
      # (ADR 0045 D1) so attribution can't bypass the closed-name guarantee.
      # Applies to both zone owners and entry owners; owner is optional, so a
      # nil owner is not an error.
      def self.validate_owners!(zones, entries)
        Array(zones).each_with_index do |z, i|
          check_owner!(z["owner"], "$.zones[#{i}]")
        end
        Array(entries).each_with_index do |e, i|
          check_owner!(e["owner"], "$.entries[#{i}]")
        end
      end

      def self.check_owner!(owner, path)
        return if owner.nil?
        return if valid_owner?(owner)

        raise BadManifest.new(
          "invalid owner '#{owner}' at '#{path}' " \
          "(expected <archetype> or <archetype>:<subject>, " \
          "archetype one of: #{Textus::Role::NAMES.join(", ")})",
        )
      end

      # The owner-validation rule: an `owner:` token is either a bare archetype
      # (`agent`) or `<archetype>:<subject>` (`human:patrick`). The archetype is
      # gated against the closed Role::NAMES set (so attribution can't smuggle in
      # a name the role side rejects, ADR 0045 D1); the subject is the free-form
      # principal, validated by OWNER_SUBJECT_PATTERN. Split on the FIRST ':'
      # only — a subject may not itself contain ':' (the pattern excludes it), so
      # `human:a:b` is rejected.
      def self.valid_owner?(token)
        return false unless token.is_a?(String) && !token.empty?

        archetype, subject = token.split(":", 2)
        return false unless Textus::Role::NAMES.include?(archetype)
        return true if subject.nil?

        OWNER_SUBJECT_PATTERN.match?(subject)
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

      # Write authority is derived from capabilities (ADR 0030): a zone of a
      # given kind can only be written by a role that holds the kind's required
      # verb. Reject a manifest declaring a zone whose required verb is held by
      # no role. Capabilities.resolve returns the defaults when `roles:` is nil,
      # so the capability union is all four verbs and every kind is satisfied.
      def self.validate_zone_kind_consistency!(raw)
        held = Capabilities.resolve(raw["roles"]).values.flatten.uniq

        Array(raw["zones"]).each_with_index do |z, i|
          verb = KIND_REQUIRES_VERB[z["kind"]]
          next if verb.nil? || held.include?(verb)

          raise BadManifest.new(
            "zone '#{z["name"]}' (#{z["kind"]}) at '$.zones[#{i}]' " \
            "needs a role with capability '#{verb}'; none declared",
          )
        end
      end
    end
  end
end
