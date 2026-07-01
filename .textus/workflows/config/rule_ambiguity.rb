# Validates that no entry matches two+ rule blocks at the same specificity.
# Replaces Doctor::Check::RuleAmbiguity as a self-contained validation workflow.
# Runs on drain via match pattern, publishes results to artifacts.doctor.rule-ambiguity.

SLOTS = Textus::Manifest::Schema::FIELD_REGISTRY
         .select { |_, m| m[:in_ambiguity] }.keys.freeze

Textus.workflow "rule-ambiguity" do
  match "artifacts.doctor.rule-ambiguity"

  step :scan do |_, ctx|
    manifest = ctx.container.manifest
    rules = manifest.rules
    issues = []
    manifest.data.entries.each do |mentry|
      matches = rules.explain(mentry.key)
      next if matches.length < 2

      SLOTS.each do |slot|
        carriers = matches.select { |b| b.public_send(slot) }
        next if carriers.length < 2

        by_spec = carriers.group_by { |b| Textus::Manifest::Policy::Matcher.specificity(b.match) }
        tied = by_spec.values.select { |g| g.length > 1 }
        tied.each do |group|
          globs = group.map(&:match).sort
          issues << {
            "code" => "rule.ambiguity", "severity" => "warning",
            "subject" => mentry.key,
            "message" => "entry '#{mentry.key}' matches #{group.length} rule blocks at the same " \
                         "specificity for #{slot}: #{globs.join(", ")}",
            "fix" => "narrow one of the conflicting match: globs so a single block wins for this key",
          }
        end
      end
    end
    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
