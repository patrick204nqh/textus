## 12. Conformance fixtures

A conformant implementation MUST pass these fixtures (the reference test suite ships a YAML file listing inputs and expected envelopes):

**Fixture A — Resolve and read:**
Given a manifest with `working.network.org` → `working/network/org` (nested), schema `person`, and a file `.textus/data/working/network/org/jane.md` with valid frontmatter, `textus get working.network.org.jane --output=json` returns the canonical envelope with `etag` matching the file's sha256.

**Fixture B — Role gate on write:**
Given a manifest entry where `key: identity.self` lives in the `identity` lane (`kind: canon`, requiring the `author` capability), `textus put identity.self --stdin --as=agent` (where `agent` holds only `propose`) returns the error envelope with `code: "write_forbidden"` and exit code 1.

**Fixture C — Schema violation:**
Given the `person` schema and a `put` whose frontmatter omits `relationship`, the result is the error envelope with `code: "schema_violation"`, `details.missing: ["relationship"]`, and exit code 1.

**Fixture D — Staleness detection:**
Given a manifest entry `artifacts.feeds` with `kind: produced` and a `retention: { ttl: 1h }` rule, and an envelope on disk whose `_meta.last_fetched_at` is older than `now - ttl`, `textus pulse --output=json` lists `artifacts.feeds` in its `stale` array (the lifecycle scan classifies it `expired`). The scan is pure: producing this verdict does NOT trigger a re-materialise.

**Fixture E — Workflow produce:**
Given a manifest entry `artifacts.feeds.skills` with `kind: produced` and `source: { from: external, command: "true", sources: [] }` and a matching `Textus.workflow` block, `textus drain --prefix=artifacts.feeds.skills` produces the entry's **data** on disk (serialized per `format:`) matching the workflow's returned content. The output is content-addressed (no `generated_at` timestamp, ADR 0070), so re-running with unchanged sources reproduces it byte-for-byte and writes nothing.

**Fixture F — ERB render at publish:**
Given a produced entry with a to-target `{ to:, template: <name> }`, `textus drain` renders the entry's stored data through the named ERB template (under `.textus/templates/`) and emits a file whose contents match the expected rendered output byte-for-byte (after trailing-newline normalization). Two to-targets with different templates produce different bytes from the one entry.

**Fixture G — Copy publish:**
Given a manifest entry with a templateless to-target `publish: [{ to: <path> }]`, a successful `textus drain` for that entry leaves a plain file at `<path>` whose contents are the entry's content re-serialized without `_meta` (byte-identical to a clean consumer config), accompanied by a sentinel at `.textus/.run/sentinels/<path>.textus-managed.json` recording `source`, `target`, `sha256`, and `mode: "copy"`. Re-running `drain` is idempotent.

**Fixture H — Audit log format:**
Every successful write verb (`put`, `key_delete`, `key_mv`, `accept`, `schema migrate`) appends exactly one line per affected key to the audit log, in the canonical format defined in §audit (timestamp, actor role, verb, key, etag-before, etag-after). Convergence (`drain`/`serve`) writes through these same verbs (`put` for a produced entry, `key_delete` for a swept one), so it appends per the underlying write, not under a distinct `drain` verb. No write produces zero or multiple lines per key.

**Fixture I — Pending → accept:**
Given a proposal entry `proposals.knowledge.self.patch` proposing a change to `knowledge.identity.self`, `textus accept proposals.knowledge.self.patch --as=human` copies the patch body into the target key, deletes the proposal entry, and appends two audit lines (one for the target write, one for the proposals delete) in that order.
