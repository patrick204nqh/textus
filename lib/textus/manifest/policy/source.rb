module Textus
  class Manifest
    class Policy
      # An entry's external-generator declaration. `source:` now means ONLY
      # `from: external` — out-of-band runner; textus never invokes it, only
      # detects drift (doctor generator_drift check).
      # `from: fetch` and `from: derive` are removed; those concerns now live
      # in workflow files under .textus/workflows/.
      class Source
        attr_reader :command, :sources

        def initialize(raw)
          from = raw["from"].to_s
          unless from == "external"
            raise Textus::BadManifest.new(
              "from: #{from} is removed — use a workflow file under .textus/workflows/ instead",
            )
          end

          @command = raw["command"] or
            raise Textus::BadManifest.new("source (from: external) requires a `command:` field")
          @sources = raw["sources"] || []
        end

        def external? = true
        def kind      = :external
      end
    end
  end
end
