Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :put, "Create or update an entry. Schema-validated. Returns {uid, etag}.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                  description: "dotted entry key, e.g. 'knowledge.project'; must resolve to a zone the role may write"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :meta, type: Hash, wire_name: :_meta,
                                                  description: "frontmatter; reads back as `_meta`. Schema-validated — call `schema KEY` first"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :body,
                                                  description: "markdown/text payload for md entries; use `content` for json/yaml"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :content, type: Hash,
                                                  description: "structured payload for json/yaml-format entries; omit (use `body`) for markdown entries"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :if_etag,
                                                  description: "optimistic-concurrency guard; write rejected if entry changed since")],
    %i[cli mcp], :write
  ),
)
