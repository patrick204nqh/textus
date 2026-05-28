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

      def role_mapping
        @data.role_mapping
      end

      def role_kind(name)
        @data.role_mapping[name]
      end

      def roles_with_kind(kind)
        @data.role_mapping.each_with_object([]) { |(name, k), acc| acc << name if k == kind }
      end
    end
  end
end
