# frozen_string_literal: true

module Textus
  module Domain
    # Authorization service. Single source of truth for "given a manifest
    # entry and a role, may this caller read/write?". Extracted from
    # Application::Context so the rule lives in Domain alongside Permission.
    class Authorizer
      def initialize(manifest:)
        @manifest = manifest
      end

      def can_write?(zone, role:)
        @manifest.policy.permission_for(zone.to_s).allows_write?(role)
      end

      def can_read?(zone, role:)
        @manifest.policy.permission_for(zone.to_s).allows_read?(role)
      end

      def authorize_write!(mentry, role:)
        return if can_write?(mentry.zone, role: role)

        writers = @manifest.policy.zone_writers(mentry.zone)
        raise WriteForbidden.new(mentry.key, mentry.zone, writers: writers)
      end

      def authorize_read!(mentry, role:)
        return if can_read?(mentry.zone, role: role)

        readers = @manifest.policy.zone_readers[mentry.zone]
        readers = nil if readers == :all
        raise ReadForbidden.new(mentry.key, mentry.zone, readers: readers)
      end
    end
  end
end
