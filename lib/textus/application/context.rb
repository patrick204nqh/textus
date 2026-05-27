require "securerandom"

module Textus
  module Application
    # A Context describes the call: who is acting (role), what request this
    # is part of (correlation_id), what time it is (now), and whether
    # writes should be suppressed (dry_run).
    #
    # Use cases pull their collaborators (manifest, file_store, bus, audit
    # log, authorizer) from constructor kwargs in Tasks 3-5. During the
    # migration, LegacyContext lets a use case read those off a paired
    # store handle so this task can land without rewriting every use case
    # in one commit.
    Context = Data.define(:role, :correlation_id, :now, :dry_run) do
      def self.build(role:, correlation_id: nil, now: nil, dry_run: false)
        new(
          role: role.to_s,
          correlation_id: correlation_id || SecureRandom.uuid,
          now: now || Time.now,
          dry_run: dry_run,
        )
      end

      # Temporary 0.19.0 migration helper. Returns a LegacyContext that
      # exposes the slim Context surface plus the historical service-locator
      # methods (manifest, bus, authorize_*) backed by a Store handle.
      # Removed before 0.19.0 ships -- Task 12 has a grep guard.
      def self.legacy(store:, role: Textus::Role::DEFAULT, correlation_id: nil, dry_run: false)
        LegacyContext.new(
          ctx: build(role: role, correlation_id: correlation_id, dry_run: dry_run),
          store: store,
        )
      end

      def dry_run? = dry_run

      def with_role(new_role)
        self.class.new(
          role: new_role.to_s,
          correlation_id: correlation_id,
          now: now,
          dry_run: dry_run,
        )
      end
    end

    # Pairs a slim Context with a Store handle, exposing the legacy
    # service-locator interface (manifest, bus, authorize_*). Use cases
    # receive an instance of this during Tasks 2-5; by end of Task 5 every
    # use case takes explicit ports instead and this class is deleted.
    class LegacyContext
      attr_reader :store

      def initialize(ctx:, store:)
        @ctx = ctx
        @store = store
      end

      # Slim Context surface
      def role            = @ctx.role
      def correlation_id  = @ctx.correlation_id
      def now             = @ctx.now
      def dry_run?        = @ctx.dry_run?

      def with_role(new_role)
        self.class.new(ctx: @ctx.with_role(new_role), store: @store)
      end

      # Service-locator surface (will be removed after Task 5)
      def manifest    = @store.manifest
      def schemas     = @store.schemas
      def file_store  = @store.file_store
      def audit_log   = @store.audit_log
      def bus         = @store.bus

      def can_write?(zone) = authorizer.can_write?(zone, role: @ctx.role)
      def can_read?(zone)  = authorizer.can_read?(zone, role: @ctx.role)
      def authorize_write!(mentry) = authorizer.authorize_write!(mentry, role: @ctx.role)
      def authorize_read!(mentry)  = authorizer.authorize_read!(mentry, role: @ctx.role)

      private

      def authorizer
        Textus::Domain::Authorizer.new(manifest: @store.manifest)
      end
    end
  end
end
