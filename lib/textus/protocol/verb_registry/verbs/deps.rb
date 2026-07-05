Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :deps, "List the keys a derived entry depends on.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                 description: "dotted key of the derived entry whose source keys you want")],
    %i[cli mcp], :read
  ),
)
