module Textus
  class Manifest
    # Authority over zones and roles derived from a Manifest::Data snapshot.
    # Encapsulates the lookups previously living on Manifest itself
    # (zone_writers, zone_kinds, permission_for, role_kind, roles_with_kind).
    class Policy
      def initialize(data)
        @data = data
        @zone_kinds_cache = {}
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

      def zone_kinds(zone_name)
        @zone_kinds_cache[zone_name] ||= zone_writers(zone_name).each_with_object(Set.new) do |w, acc|
          k = role_kind(w)
          acc << k if k
        end.freeze
      end

      # The kind declared on a zone in the manifest, or nil if undeclared.
      def declared_kind(zone_name)
        @data.declared_zone_kinds[zone_name]
      end

      # The single zone declaring `kind: queue`, or nil. Schema guarantees <=1.
      def queue_zone
        @data.declared_zone_kinds.key(:queue)
      end

      # A zone is derived if it declares `kind: derived` or (back-compat) its
      # writers include a generator role.
      def derived_zone?(zone_name)
        declared_kind(zone_name) == :derived || zone_kinds(zone_name).include?(:generator)
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

      # The zone a proposer role writes proposals into. Prefers the zone that
      # declares `kind: queue` (when the role can write it); falls back to the
      # legacy "first writable zone whose name contains review" convention for
      # manifests that have not adopted zone kinds yet.
      def propose_zone_for(role)
        return nil if role.nil?

        q = queue_zone
        return q if q && zone_writers(q).include?(role)

        @data.zones.find { |zname, writers| writers.include?(role) && zname.include?("review") }&.first
      end
    end
  end
end
