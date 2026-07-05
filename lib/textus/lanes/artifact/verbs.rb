module Textus
  module Lanes
    module Artifact
      module Verbs
        Textus::Protocol::VerbRegistry.register(
          Textus::Protocol::VerbRegistry::VerbSpec.new(
            :workflow_spec, "Return the full definition of a named workflow — match, steps, publish targets.",
            [Textus::Protocol::VerbRegistry::ArgSpec.arg(
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
