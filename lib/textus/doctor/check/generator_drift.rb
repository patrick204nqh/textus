module Textus
  module Doctor
    class Check
      # ADR 0079: generator/build drift — a derived/external entry whose sources
      # changed since its generated.at. Dependency-based (not age-based), so it
      # stays OUT of the lifecycle/freshness unification and lives here as a
      # health signal. This is the surviving home for what the removed `stale`
      # verb reported.
      class GeneratorDrift < Check
        def call
          gen = Textus::Domain::Staleness::GeneratorCheck.new(
            manifest: manifest,
            file_stat: Textus::Ports::Storage::FileStat.new,
          )
          manifest.data.entries.flat_map { |m| gen.rows_for(m) }.map do |row|
            {
              "code" => "generator_drift",
              "level" => "warning",
              "subject" => row["key"],
              "message" => row["reason"],
              "fix" => "rematerialize the entry: `textus reconcile`",
            }
          end
        end
      end
    end
  end
end
