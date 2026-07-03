---
name: '0126-protocol-textus-4-manifest-data-shape'
uid: ''
supersedes: ['0034-unify-lane-vocabulary', '0045-close-role-name-set']
---

# ADR-0126: Protocol textus/4 — roles/lanes hardcoded in code, manifest adopts data: shape

## Status

Accepted.

## Supersedes

- ADR 0034 — Unify lane vocabulary (the lane-kind→capability table moved from manifest to hardcoded protocol constant)
- ADR 0045 — Close role-name set (the role vocabulary moved from manifest to hardcoded protocol constant)

## Context

ADR 0034 established `Schema::LANES` as the single source of truth for the zone-kind/capability bijection, declared in the manifest via `lanes:`. ADR 0045 closed role names to `{human, agent, automation}`, declared in the manifest via `roles:`. Both were necessary steps that converged on a stable, closed vocabulary.

With the vocabulary stable across every shipped store (the init scaffold, the dogfood `.textus/`, all examples), the manifest no longer needs to declare what never varies. Every valid store uses exactly the same five lanes and three roles.

Separately, the manifest's entry declarations carried vestigial fields:
- `owner:` — attribution that was never enforced by the write gate
- `kind: produced` — a marker that duplicated the lane name (`artifacts`), with no behavioral distinction from `Leaf`
- `kind: nested, nested: true` — kind inference from disk state was already implemented; the manifest-level annotation was decorative for entries whose directories existed

## Decision

1. **Roles and lanes are hardcoded in `Textus::Protocol::V4`, not declared in the manifest.** The `roles:` and `lanes:` top-level keys are rejected by `Data.parse` with a clear error pointing to the protocol change.

2. **Entries are grouped by lane under a `data:` key.** The manifest shape changes from flat `entries:` to grouped `data:\n  <lane>:\n    - { key: ..., ... }`. This makes the lane association structural (the key is the group key) rather than a per-entry field, reducing repetition.

3. **Kind is always inferred from disk** — `File.directory?` → `:nested`, `File.file?` → `:leaf`, absent → `:leaf`. The `Produced` entry class is removed entirely. Entries in the `artifacts` lane are classified by disk state like any other lane; `derived_entry?` is now a `lane == "artifacts"` check.

4. **`owner:` is removed from entry declarations.** It was advisory only — attribution belongs in the entry content or the `_meta` envelope, not in the manifest schema.

5. **`format: json` entries no longer need `kind: produced`.** The format is sufficient; kind is inferred.

## Consequences

- **Manifests are shorter and have fewer decorative fields.** A typical entry is `{ key: docs.readme, format: json }`.
- **The `Produced` entry class is deleted** (126 lines). Consumers that checked `is_a?(Produced)` now check `lane == "artifacts"`.
- **Roles/lanes are no longer operator-configurable.** This was accepted in ADR 0045 (Q1: "strictly hardcoded"). The lane kind→capability mapping is equally immutable.
- **All existing `textus/3` manifests are structurally incompatible** — `roles:`, `lanes:`, `owner:` at the top level, and `kind: produced` in entries all trigger `BadManifest`. The protocol version `textus/4` signals this break. An automatic migration path is deferred.
- **`owner:` in lane declarations** (e.g. `{ name: scratchpad, owner: agent }`) is also dropped — it was used only by the init scaffold and the `boot` envelope, and was advisory there too.
- **The manifest explicitly names only what varies:** entries (keys + their lane grouping) and, optionally, format/path/schema/publish/ignore per entry. Roles, lanes, and their capabilities are protocol constants.

## Alternatives considered

- **Keep roles/lanes in manifest but validate against protocol.** Rejected: if they never vary, requiring them in the manifest is busywork. Every init-run store and every test fixture repeats the same five lanes. Removing them is simpler and makes the protocol version the authoritative declaration.

- **Keep `Produced` as an inference from lane name.** Rejected: `lane == "artifacts"` is a one-line check; a whole entry subclass adds indirection with no behavioral value. The class was only ever distinguished by its lane membership.

- **Keep `owner:` as optional.** Rejected: it was never enforced. If attribution is needed at the semantic layer, it belongs in the entry body or the `_meta` envelope, not in the manifest schema.
