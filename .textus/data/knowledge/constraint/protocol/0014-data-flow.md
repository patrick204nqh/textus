# Data Flow Architecture

## Entry Points

### CLI Surface
```
argv → CLI.run → Verb::Get#invoke → store.get(key:)
                                    → Gen*#invoke → Runner.dispatch → store.public_send(verb, **inputs)
```

### MCP Surface
```
JSON-RPC → Server#dispatch → Catalog.call → Projector.dispatch → store.public_send(verb, **bound)
```

### Common pipeline (all converge at Store#method_missing)
```
Store#method_missing
  → Binder.command(spec, kwargs) → Pending(spec, inputs)
  → Pipeline.dispatch(pending, call:)
    → Binder → Trace → Auth → AuditIndex
    → HandlerRegistry.for(Contract) → UseCase.call(command, call, deps)
```

### Bypass paths (direct Reader/Writer, no use case)
- ContainerProxy#read_family, Retention, Produce::Publisher
- Workflow::Runner, Boot artifacts, Doctor::Check
- No auth, no audit, no events on these paths
