Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :pulse, "Delta since cursor — changed entries, pending proposals, index freshness.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :since, type: Integer,
                                                  description: "audit seq to diff from; defaults to the session cursor")],
    %i[cli mcp], :read
  ),
)
