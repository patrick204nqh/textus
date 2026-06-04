module Textus
  module Doctor
    class Check
      # ADR 0079 (additive window): fetch:/retention: are superseded by
      # lifecycle:. Warn until `lifecycle migrate` is run; Plan 2 removes the
      # slots entirely.
      class LegacyLifecycleSlot < Check
        def call
          manifest.data.entries.filter_map do |mentry|
            set = manifest.rules.for(mentry.key)
            next unless set.fetch || set.retention

            slot = set.fetch ? "fetch" : "retention"
            {
              "code" => "lifecycle.legacy_slot",
              "level" => "warning",
              "subject" => mentry.key,
              "message" => "rule slot #{slot}: is superseded by lifecycle: (ADR 0079)",
              "fix" => "run `textus lifecycle migrate` to rewrite it",
            }
          end
        end
      end
    end
  end
end
