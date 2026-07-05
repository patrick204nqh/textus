Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :graph, "Query the link graph — neighbors (direct links) or reachable (transitive, with optional depth limit).",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, required: true, positional: true,
                                                  description: "entry key to query"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :depth, type: Integer,
                                                  description: "max traversal depth for reachable query (unlimited when omitted)")],
    %i[cli mcp], :read
  ),
)
