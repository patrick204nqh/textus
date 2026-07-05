Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :boot, "Return the orientation contract: lanes, agent_quickstart, agent_protocol.",
    [], %i[cli mcp], :read
  ),
)
