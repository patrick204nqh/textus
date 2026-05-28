require "securerandom"

module Textus
  # Immutable per-invocation value. Replaces Application::Context.
  Call = Data.define(:role, :correlation_id, :now, :dry_run) do
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
