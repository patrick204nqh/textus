module Textus
  module Lanes
    module Scratchpad
      module Verbs
      end
    end
  end
end

Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :session_open, summary: "Create a new agent session with workspace directories.",
    args: [], surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :session_close, summary: "Seal an active session by ID.",
    args: [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :session_id, required: true,
                                                       description: "UUID of the session to close")],
    surfaces: %i[cli mcp], category: :write,
    lane: :scratchpad
  ),
)
