module Textus
  module Lanes
    module Knowledge
      module Actions
      end
    end
  end
end

Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :loop, summary: "Return the knowledge loop structure — node names and flow order.",
    args: [], surfaces: %i[cli mcp], category: :read,
    lane: :knowledge
  ),
)
