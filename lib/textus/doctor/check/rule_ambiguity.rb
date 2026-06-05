module Textus
  module Doctor
    class Check
      # Flags entries whose key is matched by two or more rule blocks of the
      # SAME specificity in the same slot (lifecycle / handler_allowlist /
      # guard / materialize). Ties are non-deterministic in the parser's pick step, so
      # they're a configuration smell — surface them.
      class RuleAmbiguity < Check
        SLOTS = Textus::Manifest::Schema::FIELD_REGISTRY.select { |_, m| m[:in_ambiguity] }.keys.freeze

        def call
          out = []
          rules = manifest.rules
          manifest.data.entries.each do |mentry|
            matches = rules.explain(mentry.key)
            next if matches.length < 2

            SLOTS.each { |slot| out.concat(ambiguities_for(mentry, slot, matches)) }
          end
          out
        end

        private

        def ambiguities_for(mentry, slot, matches)
          carriers = matches.select { |b| b.public_send(slot) }
          return [] if carriers.length < 2

          by_specificity = carriers.group_by { |b| Textus::Domain::Policy::Matcher.specificity(b.match) }
          tied = by_specificity.values.select { |group| group.length > 1 }
          tied.map { |group| issue_for(mentry, slot, group) }
        end

        def issue_for(mentry, slot, group)
          globs = group.map(&:match).sort
          {
            "code" => "rule.ambiguity",
            "level" => "warning",
            "subject" => mentry.key,
            "message" => "entry '#{mentry.key}' matches #{group.length} rule blocks at the same " \
                         "specificity for #{slot}: #{globs.join(", ")}",
            "fix" => "narrow one of the conflicting match: globs in .textus/manifest.yaml so a single " \
                     "block wins for this key",
          }
        end
      end
    end
  end
end
