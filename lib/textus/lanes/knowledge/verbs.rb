module Textus
  module Lanes
    module Knowledge
      module Verbs
      end
    end
  end
end

Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :loop, summary: "Return the knowledge loop structure — node names and flow order.",
    args: [], surfaces: %i[cli mcp], category: :read,
    lane: :knowledge
  ),
)
