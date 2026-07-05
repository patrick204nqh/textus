Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :uid, "Return the stable UID of an entry without reading its body.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                 description: "entry key")],
    %i[cli mcp], :read
  ),
)
