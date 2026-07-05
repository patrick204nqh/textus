Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :session_open, "Create a new agent session with workspace directories.",
    [], %i[cli mcp], :write
  ),
)
