Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :blame, "Annotate audit rows with the git commit that introduced each file state.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                  description: "entry key to blame"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :limit, type: Integer,
                                                  description: "maximum number of audit rows to return")],
    %i[cli mcp], :read
  ),
)
