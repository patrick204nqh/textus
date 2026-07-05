Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :list, "List keys filtered by lane and/or prefix.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :prefix,
                                                  description: "restrict to keys starting with this dotted prefix, e.g. 'knowledge.execution'"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :lane,
                                                  description: "restrict to one lane by name (see `boot` lanes)"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :q,
                                                  description: "full-text search query over entry content (FTS5)"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :schema,
                                                  description: "filter to entries whose schema matches this name")],
    %i[cli mcp], :read
  ),
)
