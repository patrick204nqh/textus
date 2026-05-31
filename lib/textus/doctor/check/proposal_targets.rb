module Textus
  module Doctor
    class Check
      # Flags pending proposals whose `proposal.target_key` cannot ever be
      # accepted: it points at a non-canon zone or resolves to no declared
      # entry (ADR 0035). Reads the live queue zone; silent when there is no
      # queue zone. Warnings, not errors — they are stale junk, not store
      # corruption (the accept gate already refuses them).
      class ProposalTargets < Check
        def call
          queue = manifest.policy.queue_zone
          return [] unless queue

          dispatch(:list, zone: queue).filter_map { |row| issue_for(row["key"]) }
        end

        private

        def issue_for(key)
          target = dispatch(:get, key).meta&.dig("proposal", "target_key")
          return nil if target.nil? # not a proposal entry — skip

          zone = manifest.resolver.resolve(target).entry.zone
          return nil if manifest.policy.declared_kind(zone.to_s) == :canon

          {
            "code" => "proposal.target_not_canon",
            "level" => "warning",
            "subject" => key,
            "message" => "proposal '#{key}' targets '#{target}' in zone '#{zone}' (not canon); it can never be accepted",
            "fix" => "delete the proposal, or repoint target_key at a canon zone",
          }
        rescue Textus::UnknownKey
          {
            "code" => "proposal.target_unresolved",
            "level" => "warning",
            "subject" => key,
            "message" => "proposal '#{key}' targets '#{target}', which resolves to no declared entry",
            "fix" => "delete the proposal, or fix target_key",
          }
        end
      end
    end
  end
end
