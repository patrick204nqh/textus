Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :drain, "Seed materialize + sweep jobs then drain the queue to empty.",
    [], %i[cli mcp], :maintenance
  ),
)
