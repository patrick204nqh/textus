# examples/hello — textus in 5 commands

The smallest worked example. Two zones, one schema, one role-gated write
flow that you can demo in a single terminal scroll.

If `examples/claude-plugin/` is the full shape and `examples/project/`
is "use textus for your own project context," this one is the answer
to "I just want to see it work."

## What you'll see

- An **agent** proposes a note to the `review` zone.
- A **human** accepts the proposal — it lands in `working`.
- An attempt by the agent to write directly to `working` is **rejected**:
  the agent holds only `propose`, and the `working` origin zone needs the
  `accept` capability to write. (This is the value textus adds over
  just writing files in a folder.)
- Every write is **audited**: `textus audit` shows who-did-what.

## Run it

```sh
cd examples/hello

# 1. Orientation — what zones can which roles write?
bundle exec ../../exe/textus boot | jq '.agent_quickstart, .write_flows'

# 2. Agent proposes a note. Goes into review/ with a `proposal:` block
#    that names where it should land if a human accepts it.
printf '%s' '{
  "_meta": {
    "name": "oncall",
    "tags": ["ops"],
    "proposal": {"target_key": "working.notes.oncall", "action": "put"}
  },
  "body": "Patrick on call this week.\n"
}' | bundle exec ../../exe/textus put review.notes.oncall --as=agent --stdin

# 3. Human accepts the proposal. textus copies it to working/, audits the move.
bundle exec ../../exe/textus accept review.notes.oncall --as=human

# 4. Verify: the note is now under working/, schema-validated, with a stable uid.
bundle exec ../../exe/textus get working.notes.oncall

# 5. Show what just happened (audit log is append-only NDJSON).
bundle exec ../../exe/textus audit --limit=5
```

## Demonstrate the role gate

```sh
# Try to skip the review queue — agent writes directly to working.
# Rejected: the agent lacks the `accept` capability the origin zone needs.
# This is the load-bearing safety.
printf '%s' '{"_meta":{"name":"shortcut"},"body":"skip review\n"}' \
  | bundle exec ../../exe/textus put working.notes.shortcut --as=agent --stdin
# → write_forbidden: writing 'working.notes.shortcut' (zone 'working') needs capability 'accept'
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
      working/notes/          # human-writable (.gitkeep until first write)
      review/notes/           # agent-writable (.gitkeep until first write)
```

## What's not here

This example deliberately skips: hooks, publish (no `publish_to` / `publish_each`),
intake/refresh, derived entries, MCP. Each of those is its own chapter — see
`examples/claude-plugin/` for a worked agent integration that uses them all.

## Resetting between runs

```sh
rm -rf .textus/zones/working/notes/* .textus/zones/review/notes/*
: > .textus/audit.log
```
