Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :key_delete, "Delete one entry by key. Returns {ok, key, deleted}.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                 description: "dotted entry key to delete"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :if_etag,
                                                 description: "optimistic-concurrency guard: etag you last read")],
    %i[cli mcp], :write
  ),
)
