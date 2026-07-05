Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :get, "Read one entry — on-disk read with freshness verdict.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                 description: "dotted entry key to read, e.g. 'knowledge.project'")],
    %i[cli mcp], :read
  ),
)
