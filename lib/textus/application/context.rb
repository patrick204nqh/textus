require "securerandom"

module Textus
  module Application
    class Context
      attr_reader :store, :role, :correlation_id

      def initialize(store:, role:, correlation_id: nil, clock: Time, dry_run: false)
        @store          = store
        @role           = role.to_s
        @correlation_id = correlation_id || SecureRandom.uuid
        @clock          = clock
        @dry_run        = dry_run
        @now            = nil
      end

      def now
        @now ||= @clock.now
      end

      def dry_run?
        @dry_run
      end

      def can_write?(zone)
        store.manifest.permission_for(zone.to_s).allows_write?(role)
      end

      def can_read?(zone)
        store.manifest.permission_for(zone.to_s).allows_read?(role)
      end

      def with_role(new_role)
        self.class.new(
          store: @store,
          role: new_role,
          correlation_id: @correlation_id,
          clock: @clock,
          dry_run: @dry_run,
        )
      end
    end
  end
end
