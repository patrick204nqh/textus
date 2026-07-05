Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :key_mv_prefix, "Bulk-rename every leaf key under from_prefix to to_prefix.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :from_prefix, required: true, positional: true,
                                                 description: "dotted prefix whose leaf keys are renamed"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :to_prefix, required: true, positional: true,
                                                 description: "dotted prefix the keys are renamed to"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                                                 description: "when true, returns planned moves without applying")],
    %i[cli mcp], :write
  ),
)
