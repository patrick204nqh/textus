Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :where, "Resolve a key to its zone, owner, and path without reading the body.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                 description: "dotted key to locate")],
    %i[cli mcp], :read
  ),
)
