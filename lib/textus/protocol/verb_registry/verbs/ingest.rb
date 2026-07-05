Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    verb: :ingest, summary: "Capture external source material into the raw lane. Write-once.",
    args: [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :kind, required: true, positional: true,
                                                       description: "source kind: url | file | asset"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :slug, required: true,
                                                       description: "human slug for the key suffix (kebab-case)"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :url, description: "remote URL (required when kind=url)"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :path, description: "local file path (required when kind=file or kind=asset)"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :lane, description: "asset group subdirectory (required when kind=asset)"),
           Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :label, description: "human label stored in source.label")],
    surfaces: %i[cli mcp], category: :write, lane: :ingest
  ),
)
