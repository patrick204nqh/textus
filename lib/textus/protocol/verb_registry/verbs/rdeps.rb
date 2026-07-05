Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :rdeps, "List the derived entries that depend on a key (reverse deps).",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                 description: "dotted key whose dependents you want")],
    %i[cli mcp], :read
  ),
)
