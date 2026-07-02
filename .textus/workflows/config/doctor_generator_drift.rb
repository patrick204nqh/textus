# Replaces Doctor::Check::GeneratorDrift. Reports produced/external entries
# whose sources changed after generated.at.

Textus.workflow "doctor-generator-drift" do
  match "artifacts.doctor.generator-drift"

  step :scan do |_, ctx|
    detector = Textus::Store::Freshness::DriftDetector.new(
      manifest: ctx.container.manifest,
      file_stat: Textus::Port::Storage::FileStat.new,
      clock: Textus::Port::Clock.new,
    )

    issues = ctx.container.manifest.data.entries.flat_map { |entry| detector.drift_rows(entry) }.map do |row|
      {
        "code" => "generator_drift",
        "level" => "warning",
        "subject" => row["key"],
        "message" => row["reason"],
        "fix" => "rematerialize the entry: `textus drain`",
      }
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
