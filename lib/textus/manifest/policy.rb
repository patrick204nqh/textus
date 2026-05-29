module Textus
  class Manifest
    # Authority over zones and roles derived from a Manifest::Data snapshot.
    # Encapsulates the lookups previously living on Manifest itself
    # (zone_writers, permission_for, role_kind, roles_with_kind). Derived /
    # proposal-queue status is authoritative via the declared-kind family
    # (declared_kind, derived_zone?, queue_zone?, queue_zone), not inferred
    # from writers.
    class Policy
      def initialize(data)
        @data = data
      end

      def zone_writers(zone_name)
        @data.zones[zone_name] or raise UsageError.new("undeclared zone '#{zone_name}'")
      end

      def zone_readers
        @data.zone_readers
      end

      def permission_for(zone_name)
        Textus::Domain::Permission.new(
          zone: zone_name,
          write_policy: zone_writers(zone_name),
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

      def role_mapping
        @data.role_mapping
      end

      def role_kind(name)
        @data.role_mapping[name]
      end

      def roles_with_kind(kind)
        @data.role_mapping.each_with_object([]) { |(name, k), acc| acc << name if k == kind }
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
