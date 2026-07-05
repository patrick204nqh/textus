Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :schema_list, "List all registered schemas with their fields.",
    [], %i[cli mcp], :read
  ),
)
