require "securerandom"

module Textus
  module Application
    # A Context describes the call: who is acting (role), what request this
    # is part of (correlation_id), what time it is (now), and whether
    # writes should be suppressed (dry_run).
    #
    # Collaborators (manifest, file_store, bus, audit log, authorizer) are
    # never read from Context — use cases pull them from a Caps record
    # (Read/Write/Hook) that Session derives from the Store.
    Context = Data.define(:role, :correlation_id, :now, :dry_run) do
      def self.build(role:, correlation_id: nil, now: nil, dry_run: false)
        new(
          role: role.to_s,
          correlation_id: correlation_id || SecureRandom.uuid,
          now: now || Time.now,
          dry_run: dry_run,
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
  end
end
