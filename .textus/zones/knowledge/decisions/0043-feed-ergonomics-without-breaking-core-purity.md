# ADR 0043 — Feed ergonomics without breaking core purity: an intake cookbook, and environment as a `feeds.machine` snapshot

**Date:** 2026-06-01
**Status:** Proposed
**Refines:** [ADR 0037](./0037-boot-pulse-derive-or-guard.md) (boot/pulse derive-or-guard), [ADR 0038](./0038-runtime-artifacts-under-run-and-layout.md) (`Layout` owns the on-disk map + generated `.gitignore`), [ADR 0034](./0034-unify-lane-vocabulary.md) (zone-kind/capability bijection), [ADR 0008](./0008-freshness-and-resolution-types.md) (freshness model). Governed by **SPEC §5.4** (intake makes no implicit network calls).

## Context

Two recurring asks push on the `feeds` zone, and both run straight into
load-bearing invariants. They are worth deciding together because the *same*
invariant decides both.

**The invariant.** SPEC §5.4 states it directly: an intake handler "only runs
when explicitly invoked," and *"textus itself still makes no implicit network
calls."* The built-ins that ship today are **parsers, not fetchers** —
`json`, `csv`, `markdown-links`, `ical-events`, `rss` each read raw bytes from
`config["bytes"]` and emit structured output (`lib/textus/hooks/builtin.rb`).
The I/O is the caller's; the parse is textus's. This is what lets `textus/3` be
"a wire format any language can speak": the more the reference gem does at
runtime, the more every other implementation must reproduce to stay conformant.

**Ask 1 — external APIs.** To pull a URL into `feeds` today, a user writes a
Ruby `:resolve_intake` hook that does `Net::HTTP` and stuffs the bytes into a
parser. Everyone re-writes the same glue. The temptation is to ship a built-in
HTTP fetcher. That would be the first thing in the codebase to perform implicit
I/O, and it drags a large surface behind it: credentials/secret handling, TLS,
retries, timeouts, proxies, and SSRF (a config-declared `url:` the core
dereferences is an SSRF sink the moment any untrusted manifest exists).

**Ask 2 — current environment.** Agents want ambient context — git HEAD,
branch, dirty state, `now`, versions. The intuitive placements are both wrong:

- *A `feeds`/`quarantine` intake.* Quarantine means "external bytes pending
  validation." Ambient local state is not pending anything, and the freshness
  model (ADR 0008: `ttl`, `on_stale`, `stale: true`) is meaningless for data
  that is stale the instant it is read.
- *A live scan inside `boot`/`pulse`.* This breaks ADR 0037 on two fronts.
  `boot` is documented as side-effect-free; a scan shells out (fork/exec).
  And 0037 makes every agent-facing fact either *derived from the manifest* or a
  *fixture-guarded* editorial copy — ambient env is neither, so it cannot be
  guarded. The sharper hazard is `pulse`, which runs **every turn** and already
  fans out to four aggregations (audit + freshness + review + doctor,
  `lib/textus/read/pulse.rb`); hanging a `git status` (100 ms+ on a large/dirty
  tree) off that path taxes the hottest loop in the system and makes its output
  non-reproducible.

Both asks are really one question — *how do we make feed data ergonomic without
moving I/O, non-determinism, or secret-handling into the pure core?*

## Decision

**1. External-API ergonomics ship as an opt-in intake *cookbook*, not as a
core built-in fetcher.** Add `docs/cookbook/intake-recipes.md`: a set of
copy-paste `:resolve_intake` recipes for common sources (HTTP JSON, RSS, iCal
URL, Notion, local file). Each recipe keeps the existing split honest — the
user-owned hook performs the I/O, then delegates the parse to a built-in:

```ruby
# .textus/hooks/http_json.rb
reg.on(:resolve_intake, :http_json) do |caps:, config:, args:|
  body = Net::HTTP.get(URI(config.fetch("url")))            # YOU own the I/O
  reg.invoke(:resolve_intake, :json, config: { "bytes" => body })  # built-in parser
end
```

Core is untouched: no new gem, no implicit network, SSRF/credentials/retries
live in the user's hook where the trust boundary already is. The cookbook
removes the blank-page problem without weakening SPEC §5.4.

**2. Current environment is a *feed* — `feeds.machine`, fetched by `automation`.**
The machine the store runs on (local or server) is an *external source*; reading
git / host / runtime facts from it is "going outside and bringing data in" —
which is exactly what the `fetch` capability and the `feeds` (`quarantine`) zone
are for. textus's own analogy settles it: `fetch` is the grocery shopper (goes
outside, brings ingredients home), `build` is the chef (cooks what's already in
the kitchen). Machine introspection is shopping, not cooking. So the snapshot is
a `feeds.machine` intake entry, written by `automation` via `textus fetch
feeds.machine --as=automation`, never on the `pulse`/`boot` read path. Four
properties make this concrete:

- **Not native (scaffolded, droppable).** textus ships **no built-in machine
  provider**. `textus init` scaffolds an example `:resolve_intake` hook the user
  owns and customizes, plus the `feeds.machine` entry in the manifest. A store
  that doesn't want it simply deletes the entry (and the hook). Core ships
  nothing new at runtime — parsers stay the only built-ins, so SPEC §5.4 is
  *strengthened*, not merely preserved.
- **A real feed entry — retrievable via the protocol.** `feeds.machine` is
  addressable by key (`textus get feeds.machine`, `list`, freshness) like any
  other entry. It is **not** placed under `.textus/.run/`: runtime files there
  have no key and are unreachable through the protocol. The intake handler
  returns content directly (`{ content: … }`) — no template, no projection.
- **Freshness is a feature here.** Because it is a feed, the standard `rules:`
  budget applies: `match: feeds.machine → fetch: { ttl: 1h }`. On a long-running
  server the host snapshot genuinely ages and re-fetch is meaningful — the very
  case that makes the freshness model fit rather than misfit.
- **Gitignored by default, sensitive-by-default — without reopening ADR 0038's
  no-drift `.gitignore`.** Machine info can carry sensitive values (paths,
  selected env vars) and is noisy in diffs, so the entry declares **no
  `publish_to:`** and is marked **`tracked: false`** (an *entry-level* flag).
  `init` keeps emitting a *generated* `.gitignore` (0038's invariant: generated,
  never hand-kept) — now derived from `Layout` (`.run/`) **plus the manifest's
  untracked entry paths** (`zones/feeds/machine.md`), with a guard spec asserting
  the two agree. `tracked:` is entry-level, not zone-level, so one feed is
  ignored while the rest of `feeds` stays tracked.

**3. The snapshot captures a small fixed set of safe scalars — the scaffold's
editable default.** Default in scope: git HEAD sha · branch · `dirty?` bool ·
repo root · `now` (utc iso8601) · ruby/OS version · textus version + `protocol`
id. Explicitly out of scope in the shipped scaffold: full `env`-var dump
(secret-leak surface), the full `git status` diff (unbounded), directory-tree
walks, and hostname/DNS lookups (latency + non-determinism). Because the handler
is a *user hook*, the allowlist is a sane default the user may extend — but the
scaffold ships the conservative set *and* the gitignored `tracked: false`
placement so that an over-eager edit cannot leak into git by accident.

## Consequences

**Core purity and polyglot portability are preserved — and the env path
strengthens them.** No implicit network call enters the reference gem, and no
built-in *fetcher* is created: the env reducer ships as scaffolding, not gem
code, so `textus/3` conformance grows nothing and the built-in set stays
parsers-only. SPEC §5.4 stands unamended.

**The orientation contract stays side-effect-free.** `feeds.machine` is pulled
only by an explicit `textus fetch`, never on the per-turn `pulse`/`boot` read
path, so 0037's guard specs keep comparing boot/pulse against reproducible
fixtures and no fork/exec is added to the hot loop.

**Sensitive-by-default, yet protocol-readable.** `feeds.machine` is a `feeds`
entry marked `tracked: false`: reachable by key through the protocol, but
gitignored and never published, so it cannot be committed or copied into a repo
file by accident. The cost is that the snapshot is local-only — orientation for
the agent working *on this host*, not shared state — and the manifest gains one
optional **entry-level** key (`tracked`) plus a `.gitignore` generator that now
reads the manifest. That generator stays the single source of truth (ADR 0038),
so no hand-maintained ignore drift is introduced.

`tracked:` is a **general entry capability**, not specific to `feeds.machine`.
It is purely declarative — it changes only `.gitignore` generation, never the
behaviour of `fetch`/`get`/`build`/freshness/guards — and it joins the existing
optional-entry-boolean family (`inject_boot`, `nested`). Any entry that is real
store content yet should not be committed (sensitive feeds carrying tokens/PII,
large or noisy fetched data, per-developer local scratch) may set it. We adopt
it as a first-class feature *now*, justified by ADR 0038: a manifest-derived
ignore is the only way to gitignore an entry without either reopening
hand-maintained-`.gitignore` drift or parking it under `.run/` where it loses
its key (and protocol addressability).

**Snapshot, not live state — by design.** The entry reflects the moment of the
last `fetch`, aged by its `ttl`. Agents needing live state run the probe
themselves.

**Additive and backward-compatible.** The cookbook is docs only; the
`feeds.machine` scaffold is opt-in `init` output a store deletes if unwanted. No
wire-format or verb change; SPEC needs no contract edit beyond documenting the
optional `tracked:` key.

## Alternatives considered

**Ship a built-in HTTP/fetch handler in core.** Rejected. It is the first
implicit-I/O in the gem and pulls credentials, TLS, retries, and SSRF into the
pure core, while forcing every other-language implementation to match it for
conformance. The pain it solves (boilerplate) is real but belongs at the edge,
where the user opts in — that is the cookbook.

**Environment as a `derived`/`build` entry (the chef).** Rejected — and this was
an earlier draft of this very ADR. `derived` means "computed from *other zones*
via projection"; the machine snapshot is computed from *outside the store*, not
from other entries, which forced an empty `select: []` and a no-op reducer — a
tell that the kind was wrong. It also misroutes the role (`build`, the chef)
when the act is `fetch` (the shopper). `feeds.machine` is the honest fit: it
keeps the role, the mechanism (intake handler returning content), and the
freshness budget all aligned.

**A dedicated `tracked: false` *zone* for the snapshot (e.g. `machine`).**
Rejected as over-built. Its only advantage over `feeds.machine` was gitignoring
a whole directory — which only mattered because an earlier draft made `tracked:`
*zone-level*. Making `tracked:` **entry-level** lets a single feed entry be
ignored while the rest of `feeds` stays tracked, so no new zone is needed.

**Live environment scan inside `boot`/`pulse`.** Rejected. Breaks "boot is
side-effect-free," makes the agent-facing output non-deterministic (un-guardable
under ADR 0037), and taxes the per-turn `pulse` hot path with fork/exec. The
snapshot model gets the same data to the agent at zero per-turn cost.

**A *native* built-in env provider (gem-shipped reducer or `:resolve_intake`).**
Rejected. It would be the first built-in to compute bytes-from-nothing — a
category change from the parsers-only set — and bakes one team's notion of
"environment" into the gem, forcing every other-language implementation to match
it for conformance. Shipping it as init-scaffolded hook + template keeps core
unchanged, lets each store define its own snapshot, and is *more* aligned with
§5.4 than a native provider would be.

**Place the snapshot under `.textus/.run/` (runtime subtree).** Rejected. It
gets gitignoring for free, but files under `.run/` are not store *entries* —
they have no key, so `textus get`/`list`/freshness cannot reach them. That
defeats the goal: the snapshot should be *readable via the protocol*. A
`tracked: false` `derived` zone keeps protocol addressability while still
suppressing git tracking; the small cost is one manifest key plus a manifest-aware
`.gitignore` generator.

**Publish the snapshot / fold it into the `CLAUDE.md` preamble (`inject_boot`).**
Rejected on security grounds. Environment can carry sensitive values; a
`publish_to:` target or an `inject_boot` preamble lands those in a committed repo
file. The snapshot stays under gitignored `.run/` with no publish target. (Also
mechanical: `inject_boot` embeds boot *into* a file rather than surfacing an
entry through boot, so it does not even achieve "agent sees env at boot.")

**Dump the full process environment / full `git status`.** Rejected on the
security and bounded-output grounds in Decision 3: secret leakage and unbounded
payloads. The shipped scaffold captures a deliberately short list of scalars.

**Do nothing (status quo: hand-write every intake hook).** Rejected as the
baseline we are improving. The split is sound; the gap is purely ergonomic, and
a cookbook + a documented environment pattern closes it without code in core.
