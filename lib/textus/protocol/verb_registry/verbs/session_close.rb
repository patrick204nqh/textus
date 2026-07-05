Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :session_close, "Seal an active session by ID.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :session_id, required: true, positional: true,
                                                  description: "UUID of the session to close")],
    %i[cli mcp], :write
  ),
)
