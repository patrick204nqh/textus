module Textus
  # Bulk and structural changes to a textus store. Each use case returns
  # a Plan when called with dry_run: true, and applies the plan when
  # called with dry_run: false.
  module Maintenance
    # A Plan is a JSON-shaped preview. Steps are op-tagged hashes the
    # use case knows how to apply. Warnings are strings surfaced to
    # the operator (skipped keys, ambiguities).
    Plan = Data.define(:steps, :warnings) do
      def to_h
        { "steps" => steps, "warnings" => warnings }
      end
    end
  end
end
