require "securerandom"

module Textus
  module Application
    class Context
      attr_reader :store, :role, :correlation_id

      def self.system(store)
        new(store: store, role: "human")
      end

      def initialize(store:, role:, correlation_id: nil, clock: Time, dry_run: false)
        @store             = store
        @role              = role.to_s
        @correlation_id    = correlation_id || SecureRandom.uuid
        @clock             = clock
        @dry_run           = dry_run
        @now               = nil
      end

      def now
        @now ||= @clock.now
      end

      def dry_run?
        @dry_run
      end

      def can_write?(zone) = authorizer.can_write?(zone, role: @role)
      def can_read?(zone)  = authorizer.can_read?(zone, role: @role)
      def authorize_write!(mentry) = authorizer.authorize_write!(mentry, role: @role)
      def authorize_read!(mentry)  = authorizer.authorize_read!(mentry, role: @role)

      def bus
        @store.bus
      end

      def manifest   = @store.manifest
      def schemas    = @store.schemas
      def file_store = @store.file_store
      def audit_log  = @store.audit_log

      def with_role(new_role)
        self.class.new(
          store: @store,
          role: new_role,
          correlation_id: @correlation_id,
          clock: @clock,
          dry_run: @dry_run,
        )
      end

      private

      def authorizer
        @authorizer ||= Textus::Domain::Authorizer.new(manifest: store.manifest)
      end
    end
  end
end
