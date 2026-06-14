# Produces verb-reference data (ADR 0097/0098) from Read::Capabilities — the
# blessed machine-readable contract projection (lib/textus/read/capabilities.rb),
# the same surface CLI/MCP/boot derive from. Depends on that stable projection,
# NOT on Dispatcher::VERBS internals (DIP).
module Textus
  module Step
    class VerbsFetch < Fetch
      def call(config:, args:, **)
        _ = config
        _ = args
        projection = Textus::Dispatch::Actions::Capabilities.new.call(container: nil, call: nil)["verbs"]
        verbs = projection.map do |row|
          {
            "name" => row["verb"],
            "summary" => row["summary"].to_s,
            "args" => Array(row["args"]).map { |a| a["name"].to_s }.sort,
          }
        end
        { "content" => { "verbs" => verbs } }
      end
    end
  end
end
