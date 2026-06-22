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
          gen = Textus::Store::Freshness::Evaluator.new(
            manifest: manifest,
            file_stat: Textus::Port::Storage::FileStat.new,
            clock: Textus::Port::Clock.new,
          )
          manifest.data.entries.flat_map { |m| gen.drift_rows(m) }.map do |row|
            {
              "code" => "generator_drift",
              "level" => "warning",
              "subject" => row["key"],
              "message" => row["reason"],
              "fix" => "rematerialize the entry: `textus drain`",
            }
          end
        end
      end
    end
  end
end
