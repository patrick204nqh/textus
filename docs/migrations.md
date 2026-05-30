# Migrations

> **How-to** · for operators · **read when** you need to restructure a store safely
> **SSoT for** store-restructuring procedures (key rename, zone rename, bulk delete) · **reviewed** 2026-05 (v0.30)

How to restructure a textus store safely.

## Bulk key rename

Rename every leaf under one prefix to another:

```sh
textus key mv --prefix old.prefix new.prefix --dry-run    # preview
textus key mv --prefix old.prefix new.prefix              # apply
```

UIDs are preserved (it's a `mv` per file). One audit row per file.

## Bulk delete

```sh
textus key delete --prefix scratch --dry-run
textus key delete --prefix scratch
```

## Rename a zone

Refuses if the destination zone directory already exists.

```sh
textus zone mv scratch sandbox --dry-run
textus zone mv scratch sandbox
```

The manifest's `zones:` list and all `entries[].zone`/`key`/`path` are rewritten; `zones/<from>/` is moved to `zones/<to>/`.

## Lint candidate rules

```sh
textus rule lint --against=./manifest.candidate.yaml
```

Diffs the candidate's `rules:` block against the live manifest. Returns `add_rule` / `remove_rule` / `change_rule` steps. No writes.

## Multi-op migration plans

Pack multiple operations into one YAML file:

```yaml
# migration-2026-06.yaml
version: 1
operations:
  - { op: key_mv_prefix, from_prefix: working.old, to_prefix: working.new }
  - { op: zone_mv,       from: scratch,            to: sandbox }
```

```sh
textus migrate ./migration-2026-06.yaml --dry-run
textus migrate ./migration-2026-06.yaml
```

Supported ops: `key_mv_prefix`, `key_delete_prefix`, `zone_mv`.

## Schema field rename (existing — see also)

The per-schema `migrate` already exists and lives under the `schema` group:

```sh
textus schema migrate FAMILY --rename=OLD_FIELD:NEW_FIELD
```

This rewrites `_meta` keys in every entry of that family.
