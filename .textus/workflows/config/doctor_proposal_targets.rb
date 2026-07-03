# Replaces Doctor::Check::ProposalTargets. Flags pending proposals targeting
# non-canon lanes or unresolved entries.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-proposal-targets" do
  match "artifacts.doctor.proposal-targets"

  step :scan do |_, ctx|
    manifest = ctx.container.manifest
    queue = manifest.policy.queue_lane
    issues = []

    unless queue.nil?
      proposals = ctx.container.pipeline.dispatch(
        Textus::Dispatch::Binder.command(Textus::VerbRegistry.for(:list), lane: queue),
        call: Textus::Value::Call.build(role: Textus::Value::Role::DEFAULT),
      )
      rows = Textus::Value::Result.extract(proposals)

      rows.each do |row|
        key = row["key"]
        envelope = ctx.container.reader.read(key)

        target = envelope&.meta&.dig("proposal", "target_key")
        next if target.nil?

        begin
          lane = manifest.resolver.resolve(target).entry.lane
          next if lane.to_s == "knowledge"

          issues << {
            "code" => "proposal.target_not_canon",
            "level" => "warning",
            "subject" => key,
            "message" => "proposal '#{key}' targets '#{target}' in zone '#{lane}' (not canon); it can never be accepted",
            "fix" => "delete the proposal, or repoint target_key at a canon zone",
          }
        rescue Textus::UnknownKey
          issues << {
            "code" => "proposal.target_unresolved",
            "level" => "warning",
            "subject" => key,
            "message" => "proposal '#{key}' targets '#{target}', which resolves to no declared entry",
            "fix" => "delete the proposal, or fix target_key",
          }
        end
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
