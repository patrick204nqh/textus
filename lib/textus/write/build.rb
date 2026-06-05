module Textus
  module Write
    # Single-pass build use case (the verb `build`, ADR 0061): dispatches
    # polymorphically to each entry's `publish_via` method — the copy-out step
    # (`publish` is the output-destination concept the verb drives, not the verb).
    # Derived entries materialize their body via Materializer; Nested entries
    # mirror their subtree via publish_tree; Leaf and Intake entries copy their
    # stored body to publish_to targets. The Build layer owns wiring (context,
    # accumulation) but not per-kind logic.
    #
    # Return shape: { "protocol", "built", "published_leaves" }
    class Build
      extend Textus::Contract::DSL

      verb     :build
      summary  "materialize derived entries; publish_to and publish_tree fan out copies"
      surfaces :cli, :mcp
      cli      "build"
      around   :build_lock
      arg :prefix, String, required: false, description: "limit the build to keys under this prefix"

      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call(prefix: nil)
        Textus::Maintenance::Materialize.new(container: @container, call: @call).call(prefix: prefix)
      end
    end
  end
end
