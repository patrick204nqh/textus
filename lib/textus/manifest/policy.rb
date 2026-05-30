module Textus
  class Manifest
    # Authority over zones and roles derived from a Manifest::Data snapshot.
    # Encapsulates the lookups previously living on Manifest itself
    # (zone_writers, permission_for). Write authority is derived from
    # capabilities × zone-kind (ADR 0030): each zone-kind requires one verb
    # (Schema::KIND_REQUIRES_VERB) and a role may write a zone iff its caps
    # include that verb (verb_for_zone, roles_with_capability). Derived /
    # proposal-queue status is authoritative via the declared-kind family
    # (declared_kind, derived_zone?, queue_zone?, queue_zone).
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
      # the accept-anchor (so it resolves to `agent`, not `human`, under the
      # default mapping). Falls back to the first proposer, then nil.
      def proposer_role
        proposers = roles_with_capability("propose")
        (proposers - roles_with_capability("accept")).first || proposers.first
      end

      # The roles authorized to write `zone_name`: those holding the verb its
      # kind requires. Raises on an undeclared zone.
      def zone_writers(zone_name)
        raise UsageError.new("undeclared zone '#{zone_name}'") unless @data.declared_zone_kinds.key?(zone_name)

        roles_with_capability(verb_for_zone(zone_name))
      end

      def zone_readers
        @data.zone_readers
      end

      def permission_for(zone_name)
        Textus::Domain::Permission.new(
          zone: zone_name,
          writers: zone_writers(zone_name),
          read_policy: @data.zone_readers[zone_name] || :all,
        )
      end

      # The kind declared on a zone in the manifest, or nil if undeclared.
      def declared_kind(zone_name)
        @data.declared_zone_kinds[zone_name]
      end

      # The single zone declaring `kind: queue`, or nil. Schema guarantees <=1.
      def queue_zone
        @data.declared_zone_kinds.key(:queue)
      end

      # A zone is derived iff it declares kind: derived.
      def derived_zone?(zone_name)
        declared_kind(zone_name) == :derived
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
