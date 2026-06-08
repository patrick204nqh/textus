require "securerandom"

module Textus
  # Immutable per-invocation value. Carries who is acting (role), the
  # request correlation id, the wall clock, and the dry_run flag — the
  # bits Use Cases need that are not part of the Container.
  Call = Data.define(:role, :correlation_id, :now, :dry_run) do
    def self.build(role:, correlation_id: nil, now: nil, dry_run: false)
      new(
        role: role.to_s,
        correlation_id: correlation_id || SecureRandom.uuid,
        now: now || Textus::Ports::Clock.new.now,
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
