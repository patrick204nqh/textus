module Textus
  class Manifest
    # Authority over zones and roles derived from a Manifest::Data snapshot.
    # Encapsulates the lookups previously living on Manifest itself
    # (zone_writers, permission_for). Write authority is derived from
    # capabilities × zone-kind (ADR 0030): each zone-kind requires one verb
    # (Schema::KIND_REQUIRES_VERB) and a role may write a zone iff its caps
    # include that verb (verb_for_zone, roles_with_capability). Derived /
    # proposal-queue status is authoritative via the declared-kind family
    # (declared_kind, derived_entry?, queue_zone?, queue_zone).
    class Policy
      def initialize(data)
        @data = data
      end

      # The capability a zone's kind requires to be written, or nil if the
      # zone declares no kind. declared_kind returns a Symbol; the table is
      # keyed by String.
      def verb_for_zone(zone_name)
        kind = declared_kind(zone_name)
        kind && Schema::KIND_REQUIRES_VERB[kind.to_s]
      end

      # Names of roles whose declared caps include `verb`.
      def roles_with_capability(verb)
        @data.role_caps.select { |_name, caps| caps.include?(verb) }.keys
      end

      # The conventional automated proposer: a role that can propose but is not
      # the author-anchor (so it resolves to `agent`, not `human`, under the
      # default mapping). Falls back to the first proposer, then nil.
      def proposer_role
        proposers = roles_with_capability("propose")
        (proposers - roles_with_capability("author")).first || proposers.first
      end

      # The role textus acts AS for a system-initiated operation requiring
      # `verb` (no human passed --as). Capability-derived — a role name that
      # exists in the manifest, or nil. Never a hardcoded literal (ADR 0044).
      def actor_for(verb)
        roles_with_capability(verb).first
      end

      # The roles authorized to write `zone_name`: those holding the verb its
      # kind requires. Raises on an undeclared zone.
      def zone_writers(zone_name)
        raise UsageError.new("undeclared zone '#{zone_name}'") unless @data.declared_zone_kinds.key?(zone_name)

        roles_with_capability(verb_for_zone(zone_name))
      end

      def permission_for(zone_name)
        Textus::Domain::Permission.new(
          zone: zone_name,
          writers: zone_writers(zone_name),
        )
      end

      # The kind declared on a zone in the manifest, or nil if undeclared.
      def declared_kind(zone_name)
        @data.declared_zone_kinds[zone_name]
      end

      # Zone names declaring `kind` (a Symbol), in manifest order. Lets callers
      # (boot) name a kind's live zone instance(s) instead of hardcoding names.
      def zones_of_kind(kind)
        @data.declared_zone_kinds.select { |_name, k| k == kind }.keys
      end

      # The single zone declaring `kind: queue`, or nil. Schema guarantees <=1.
      def queue_zone
        @data.declared_zone_kinds.key(:queue)
      end

      # ADR 0091: derived-ness is a property of the ENTRY, not its zone (one
      # machine zone holds both intake and derived entries). Resolve the entry
      # and ask it directly. Returns false if entries are not yet built
      # (validator phase during Data#initialize) — validators must not rely on
      # cross-entry state during construction.
      def derived_entry?(key)
        return false if @data.entries.nil?

        entry = @data.entries.find { |e| e.key == key } or return false
        entry.derived?
      end

      # The single zone declaring kind: machine, or nil.
      def machine_zone
        @data.declared_zone_kinds.key(:machine)
      end

      # A zone is a proposal queue iff it declares kind: queue.
      def queue_zone?(zone_name)
        declared_kind(zone_name) == :queue
      end

      # The zone a proposer role writes proposals into: the single zone that
      # declares kind: queue, when the role can write it. Returns nil if there
      # is no queue zone or the role cannot write it.
      def propose_zone_for(role)
        return nil if role.nil?

        q = queue_zone
        return nil unless q && zone_writers(q).include?(role)

        q
      end
    end
  end
end
