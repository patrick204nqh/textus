# examples/hello — textus in 5 commands

The smallest worked example. Two zones, one schema, one role-gated write
flow that you can demo in a single terminal scroll.

If `examples/claude-plugin/` is the full shape and `examples/project/`
is "use textus for your own project context," this one is the answer
to "I just want to see it work."

## What you'll see

- An **agent** proposes a note to the `proposals` zone.
- A **human** accepts the proposal — it lands in `knowledge`.
- An attempt by the agent to write directly to `knowledge` is **rejected**:
  the agent holds only `propose`, and the `knowledge` canon zone needs the
  `author` capability to write. (This is the value textus adds over
  just writing files in a folder.)
- Every write is **audited**: `textus audit` shows who-did-what.

## Run it

```sh
cd examples/hello

# 1. Orientation — what zones can which roles write?
bundle exec ../../exe/textus boot | jq '.agent_quickstart, .write_flows'

# 2. Agent proposes a note. Goes into proposals/ with a `proposal:` block
#    that names where it should land if a human accepts it.
printf '%s' '{
  "_meta": {
    "name": "oncall",
    "tags": ["ops"],
    "proposal": {"target_key": "knowledge.notes.oncall", "action": "put"}
  },
  "body": "Patrick on call this week.\n"
}' | bundle exec ../../exe/textus put proposals.notes.oncall --as=agent --stdin

# 3. Human accepts the proposal. textus copies it to knowledge/, audits the move.
bundle exec ../../exe/textus accept proposals.notes.oncall --as=human

# 4. Verify: the note is now under knowledge/, schema-validated, with a stable uid.
bundle exec ../../exe/textus get knowledge.notes.oncall

# 5. Show what just happened (audit log is append-only NDJSON).
bundle exec ../../exe/textus audit --limit=5
```

## Demonstrate the role gate

```sh
# Try to skip the proposals queue — agent writes directly to knowledge.
# Rejected: the agent lacks the `author` capability the canon zone needs.
# This is the load-bearing safety.
printf '%s' '{"_meta":{"name":"shortcut"},"body":"skip review\n"}' \
  | bundle exec ../../exe/textus put knowledge.notes.shortcut --as=agent --stdin
# → write_forbidden: writing 'knowledge.notes.shortcut' (zone 'knowledge') needs capability 'author'
```

## Layout

```
hello/
  .textus/
    manifest.yaml             # 2 zones, 2 entry families, 1 schema
    schemas/
      note.yaml               # _meta shape: name (required) + tags
    audit.log                 # append-only NDJSON, every write
    zones/
      knowledge/notes/        # human-writable (.gitkeep until first write)
      proposals/notes/        # agent-writable (.gitkeep until first write)
```

## What's not here

This example deliberately skips: hooks, publish (no `publish_to` / `publish_each`),
intake/fetch, derived entries, MCP. Each of those is its own chapter — see
`examples/claude-plugin/` for a worked agent integration that uses them all.

## Resetting between runs

```sh
rm -rf .textus/zones/knowledge/notes/* .textus/zones/proposals/notes/*
: > .textus/audit.log
```
