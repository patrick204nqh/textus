module Textus
  module Doctor
    class Check
      # ADR 0079: refresh is valid only for intake entries; drop/archive are
      # invalid for intake entries (they would re-fetch, not prune).
      class LifecycleActionInvalid < Check
        def call
          manifest.data.entries.filter_map do |mentry|
            policy = manifest.rules.for(mentry.key).upkeep&.lifecycle
            next if policy.nil?

            intake = mentry.is_a?(Textus::Manifest::Entry::Intake)
            bad = (policy.on_expire == :refresh && !intake) || (policy.destructive? && intake)
            next unless bad

            issue_for(mentry, policy, intake)
          end
        end

        private

        def issue_for(mentry, policy, intake)
          {
            "code" => "lifecycle.action_invalid",
            "level" => "error",
            "subject" => mentry.key,
            "message" => "on_expire: #{policy.on_expire} is not valid for a " \
                         "#{intake ? "intake" : "stored"} entry",
            "fix" => if intake
                       "use on_expire: refresh|warn for intake entries"
                     else
                       "use on_expire: drop|archive|warn for stored entries"
                     end,
          }
        end
      end
    end
  end
end
