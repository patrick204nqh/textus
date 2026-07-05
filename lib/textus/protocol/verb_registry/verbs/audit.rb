Textus::Protocol::VerbRegistry.register(
  Textus::Protocol::VerbRegistry::VerbSpec.new(
    :audit, "Query the audit log with optional filters.",
    [Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :key, description: "filter to rows for this key"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :lane, description: "filter to keys in this lane"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :role, description: "filter to rows written under this role"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :verb, description: "filter to rows for this verb"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :since, description: "ISO-8601 timestamp or relative offset (e.g. 1h, 30m)"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :seq_since, type: Integer, description: "return rows with seq > this cursor value"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :correlation_id, description: "filter to rows with this correlation_id"),
     Textus::Protocol::VerbRegistry::ArgSpec.arg(name: :limit, type: Integer, description: "maximum number of rows to return")],
    %i[cli mcp], :read
  ),
)
