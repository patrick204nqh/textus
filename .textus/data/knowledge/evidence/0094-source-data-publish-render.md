# ADR 0094 — `source` produces data; one publish path renders

**Date:** 2026-06-07
**Status:** Accepted
**Refines:** [ADR 0093](./0093-source-retention-over-one-reconcile-engine.md) (its engine skeleton stands — `Maintenance::Produce` at two scopes, `ProduceOnWriteSubscriber`, `Domain::Retention`, `Domain::IntakeStaleness`, reconcile's `produce → sweep` — but `source.from: template` build-then-render becomes **data, acquire-only**; rendering leaves `source:` entirely), [ADR 0052](./0052-typed-publish-block.md) (the typed `publish:` block becomes a **list of targets**; the `to:` xor `tree:` *map* forms are retired), [ADR 0049](./0049-publish-modes-as-sum-type.md) (every entry kind publishes through **one** `Publish::ToPaths` over `publish_targets` — no derived-only branch), [ADR 0070](./0070-content-addressed-build-artifacts.md) (`_meta` provenance is **preserved**, kept in the store; published artifacts stay clean — byte-identical idempotence holds).
**Touches:** [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md) (the subtree mirror survives as a `{ tree: }` *element* in the publish list — semantics unchanged), [ADR 0086](./0086-textus-owns-agent-integration-config.md) (the `provenance: false` renderer flag it introduced is **removed** — there is no publish-time provenance mechanism), [ADR 0048](./0048-fetch-subsystem-three-concerns.md)/[ADR 0075](./0075-session-opened-connect-event.md) (hook event names standardized to one convention; the fetch lifecycle + connect events are renamed).

> **One sentence:** ADR 0093 was about to collapse *acquire* and *presentation* under one `source.from` enum where `from: template` meant "internal projection rendered through a template" — so this ADR splits them onto their two honest axes: an entry's **`source:`** produces **data** (acquire-only, `from: project | handler | command`, with flat projection fields), all rendering moves to **`publish:`** (now a *list* of targets, each copying the data verbatim or rendering it through its own template), every entry kind publishes through **one** `Publish::ToPaths` path, published artifacts are **clean content** (textus's `_meta` provenance stays in the stored entry), and the hook event names are standardized to one convention.

## Context

ADR 0093 unified the former `intake:` / `compute:` / `template:` blocks into one
`source: { from: handler | template | command }` concept, discriminated by its
staleness signal. That was the right move for *acquire* — but `from: template`
quietly carried a second, unrelated job: it meant "render this projection through
a Mustache template at build time, and store the rendered bytes." A produced
entry's stored form *was* its rendered output.

That conflated two independent axes:

1. **Acquire / staleness** — *where do the bytes come from, and when are they
   stale?* An internal projection (observable upstream → `rdeps`), an external
   fetch (unobservable → `ttl`), or an out-of-band command (mtime `sources:`).
2. **Presentation** — *which template renders the bytes, and for which
   destination file?*

Folding presentation into `source.from` made the common real want
**inexpressible**: one computed dataset, rendered *differently per publish
target*. The concrete driver is this repo's own orientation data — `CLAUDE.md`
and `AGENTS.md` want the same reduced dataset rendered through their own format
templates, which a single build-time template cannot express without bespoke
handler code. The conflation also left no vocabulary for "fetch external data
**and** render it through a template" — rendering could only happen at build, and
`from: handler` produced data, so a fetched feed could never be templated without
writing the rendering into the handler.

A related smell rode along: provenance lived in **two** places — the data's
`_meta` (ADR 0070, content-addressed) *and* a publish-time `provenance:` flag /
build-time markdown header (ADR 0086). A flag that no-ops on a verbatim copy is a
split source of truth.

## Decision

### 1. `source:` produces data — acquire-only, two orthogonal axes

A produced entry's `source:` declares only **how the data is acquired** and
optionally **transformed**. It never renders. `from:` is `project | handler |
command`:

```yaml
# internal projection → data   (observable upstream → rdeps staleness)
source:
  from: project
  select: [knowledge.project, knowledge.runbooks]   # flat projection fields
  pluck: [...]                                       # optional
  sort_by: ...                                       # optional
  transform: orientation_reducer                     # optional Ruby reducer → stored data
  on_write: sync|async                               # default async; observable sources only

# external fetch → data   (unobservable upstream → ttl staleness)
source: { from: handler, handler: calendar_feed, config: { url: ... }, ttl: 1h }

# external command → opaque artifact (textus never RUNS it; staleness via sources:)
source: { from: command, command: "make build", sources: [src/*] }
```

- `from: project` **replaces** 0093's `from: template`. The Mustache template no
  longer appears in `source:`.
- Projection fields (`select`/`pluck`/`sort_by`/`transform`) are **flat** under
  `source:` — the nested `project:` block is gone.
- "Data vs opaque artifact" stops being something textus models: the store holds
  the acquired bytes (json/yaml for `project`/`handler`, whatever the command
  wrote for `command`), and publish decides how they reach a consumer.

### 2. `publish:` is a list of targets — rendering is a publish concern

`publish:` is always a **list**. There is no `Hash`/`Array` polymorphism:

```yaml
publish:
  - { to: CLAUDE.md, template: orientation.mustache, inject_boot: true }
  - { to: AGENTS.md, template: agents.mustache }     # one dataset, different render
  - { to: .mcp.json }                                 # no template → copy data verbatim
  - { tree: skills/ }                                 # ADR 0052/0047 mirror — a target shape
```

- A **to-target** carries `to:` (required, repo-relative) and optionally
  `template:` / `inject_boot:`. `template:` absent → publish the entry's content
  (verbatim copy); present → render the content through the template. Either way
  the same dataset can feed differently-formatted outputs.
- A **tree-target** carries `tree:` — the ADR 0047 subtree mirror, now just a list
  element, semantics unchanged.
- The old `publish: { to: [...] }` and `publish: { tree: ... }` *map* forms are
  retired. Entry-level / source `template:` / `inject_boot:` are retired —
  rendering lives only under a publish target.

### 3. One publish path for every entry kind

`publish_targets` (a list of `Policy::PublishTarget`) is the **single source of
truth** — the old `publish_to` array-of-strings ivar is removed. The ADR-0049
`Publish::ToPaths` mode iterates `publish_targets` and, per target, either renders
the stored data through `target.template` (`+ inject_boot`) or copies the stored
data file verbatim, then hands a `copy + sentinel` to `Ports::Publisher`. **Leaf,
nested, intake, and derived alike publish through this one mode.** A derived
entry builds its data first (`Write::DataBuilder`) and then delegates emit to the
shared mode — it has **no bespoke emit method**, and the engine never reaches into
an entry's publish internals.

Build emits data, not a render. `Builder::Pipeline` stops at `select → transform
→ store data`; `Write::Materializer` becomes `Write::DataBuilder`; the
`Renderer::Markdown` build renderer is **deleted** (its Mustache logic relocates to
a publish-time `Write::PublishRenderer`).

A `command` entry with no targets resolves to `Publish::None` → publishes nothing
→ a staleness-only signal; with targets it emits the bytes the command already
wrote into the store. This **falls out of publish-mode resolution** — there is no
`command`-specific branch in the engine.

### 4. Published artifacts are clean content — `_meta` stays in the store

Provenance lives in **one** place: the stored data's `_meta` (`from`/`reduce`,
deterministic and content-addressed per ADR 0070 — never a volatile timestamp).
Published artifacts never carry it:

- **Rendered to-target:** renders the data's content (already `_meta`-free); a
  template surfaces provenance only if it explicitly references it.
- **Verbatim to-target:** for a structured format (json/yaml) the content is
  re-serialized *without* `_meta` (so `.mcp.json` / `plugin.json` stay clean
  consumer configs, byte-identical to today); for any other / opaque format, a
  literal byte-copy.

So no `provenance: false` opt-out is needed: the store always records provenance,
published artifacts never do. The ADR 0086 renderer flag and the build-time
markdown header are both removed — one mechanism, format-agnostic, no flag that
silently no-ops.

### 5. Hook event names standardized to one convention

PubSub events read `<subject>_<past-tense>` (single-key events take the `entry_`
prefix; batch failures are `<process>_failed`); RPC events read `<verb>_<object>`.
Renames: `entry_put`→`entry_written`, `build_completed`→`entry_produced`,
`file_published`→`entry_published`, `fetch_started`→`entry_fetch_started`,
`fetch_failed`→`entry_fetch_failed`, `materialize_failed`→`produce_failed`, and the
RPC `resolve_intake`→`resolve_handler` (it dispatches on the `from: handler` name,
decoupled from the "intake" kind word). Already on-convention and unchanged:
`entry_deleted`, `entry_fetched`, `entry_renamed`, `reconcile_failed`,
`proposal_accepted`/`proposal_rejected`, `store_loaded`, `session_opened`,
`transform_rows`, `validate`. A green→green pure rename; old names fail loudly at
hook registration.

## Consequences

- **The two axes are now independently expressible.** "Where the bytes come from"
  (`source.from` → acquire/staleness) is orthogonal to "how they're presented"
  (publish templates per target). One dataset can render to differently-formatted
  targets — `CLAUDE.md` vs `AGENTS.md` — without bespoke handler code, and a
  fetched feed can be templated by adding a publish target.
- **One publish path, one provenance mechanism.** Every entry kind emits through
  `Publish::ToPaths` over `publish_targets`; provenance lives only in the stored
  `_meta`. Two latent dual-paths (a derived-only emit branch; data `_meta` +
  publish-flag provenance) are closed.
- **The `kind:` (`derived`/`intake`) vs `source.from` taxonomy is now redundant**
  (they encode the same fact — `from: handler ⟺ intake`, `from: project|command
  ⟺ derived` — and `from_raw` must validate they agree); collapsing it is a
  scheduled follow-on ADR, deliberately deferred so this change stays focused and
  low-risk.
- **Accepted uniformity tax.** Build serializes data to disk; publish reads it
  back and re-parses to feed a template — the fresh in-memory data is intentionally
  *not* threaded through, so the publish path is identical whether the data was
  just built (`project`), just fetched (`handler`), already present (`command`), or
  being re-published without a rebuild. json/yaml round-trips are lossless; one
  path beats a fast/slow dual-path. Recorded so it is not "optimized" into two
  paths later.
- **Breaking** — manifest schema: entry-level `template:`/`inject_boot:`/
  `provenance:`, `source: { from: template }`, and the *map* `publish:` forms
  (`{ to: [...] }`, `{ tree: ... }`) are each **rejected at load** with a fold hint
  (`from: template` → `from: project`; `publish:` is a list; rendering/provenance
  move). Hook event names are renamed (old names fail at registration). A produced
  entry's stored form is now **data** — `orientation` moves from rendered `.md` to
  the reducer's `.json`. Load hints make the manifest migration mechanical; no
  back-compat shim (pre-1.0).
- **Kept from 0093 unchanged:** `Domain::Retention`, `Domain::IntakeStaleness`, the
  two-scope `Maintenance::Produce` skeleton, `ProduceOnWriteSubscriber`, reconcile's
  `produce → sweep`, and the orthogonal `retention:` rule slot.

## Alternatives considered

- **0093 as written (`source.from: handler|template|command`, build-time
  template).** Rejected: collapses acquire and presentation; cannot render one
  dataset to differently-formatted targets; has no "fetch external data *and*
  template it" vocabulary.
- **Explicit three-stage pipeline (`acquire:` / `transform:` / `publish:`, with
  staleness *derived* from the acquire stage).** A cleaner pure-pipeline form, but
  a larger break that discards more in-flight 0093 work and is more verbose for the
  common diagonal. Rejected in favor of keeping `source.from` as the explicit
  acquire/staleness label.
- **Keep build-time templates, only add per-target publish templates.** Rejected:
  two template layers, two render seams; the entry stays a *render* rather than
  *data*, and the conflation it was meant to remove survives at build time.
- **Derived-only publish path + engine-driven emit (the first draft of this
  design).** Rejected after review: it created two publish mechanisms and leaked an
  entry's publish internals to the engine. Unified onto the one `Publish::ToPaths`
  path; the engine never calls an `emit_targets` helper.
- **Dual provenance (data `_meta` *and* a publish-time header flag).** Rejected:
  split source of truth; the flag no-ops on verbatim copies (where it matters most).
  One model — `_meta`, in the store, never published.
