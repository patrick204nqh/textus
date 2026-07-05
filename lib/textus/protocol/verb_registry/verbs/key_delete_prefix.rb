Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :key_delete_prefix, "Bulk-delete every leaf key under prefix.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :prefix, required: true, positional: true,
                                                 description: "every leaf key under this dotted prefix is deleted"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                                                 description: "when true, returns keys that would be deleted without deleting")],
    %i[cli mcp], :write
  ),
)
