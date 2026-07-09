module Textus
  module Lanes
    module Artifact
      module Actions
        Textus::Protocol::ActionRegistry.register(
          Textus::Protocol::ActionRegistry::ActionSpec.new(
            :workflow_spec, "Return the full definition of a named workflow — match, steps, publish targets.",
            [Textus::Protocol::ActionRegistry::ArgSpec.arg(
              name: :name, required: true, positional: true,
              description: "workflow type name (e.g. 'boot', 'decisions-log', 'materialize')"
            )],
            %i[cli mcp], :read
          ),
        )
      end
    end
  end
end
