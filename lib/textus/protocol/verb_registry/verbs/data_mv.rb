Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :data_mv, "Rename a data lane — manifest + files. Refuses if destination exists.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :from, required: true, positional: true,
                                                 description: "current data lane name"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :to, required: true, positional: true,
                                                 description: "new data lane name"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                                                 description: "when true, returns planned zone move without applying")],
    %i[cli mcp], :write
  ),
)
