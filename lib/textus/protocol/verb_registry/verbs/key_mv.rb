Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :key_mv, "Rename one entry (same zone + format). Refuses if target exists.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :old_key, required: true, positional: true,
                                                  description: "current dotted key"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :new_key, required: true, positional: true,
                                                  description: "new dotted key (same zone and format)"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :dry_run, type: :boolean,
                                                  description: "when true, returns planned move without applying")],
    %i[cli mcp], :write
  ),
)
