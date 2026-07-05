Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :schema_show, "Return the schema (field shape) for an entry's family.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                 description: "any key in the family whose schema you want")],
    %i[cli mcp], :read
  ),
)
