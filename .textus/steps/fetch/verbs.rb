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
        verbs = Textus::Action::VERBS.filter_map do |name, klass|
          next unless klass.respond_to?(:contract?) && klass.contract?

          spec = klass.contract
          {
            "name" => name.to_s,
            "summary" => spec.summary.to_s,
            "args" => spec.args.map { |a| a.wire.to_s }.sort,
          }
        end
        { "content" => { "verbs" => verbs } }
      end
    end
  end
end
