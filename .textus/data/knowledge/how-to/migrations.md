# Migrations

> **How-to** · for operators · **read when** you need to restructure a store safely
> **SSoT for** store-restructuring procedures (key rename, lane rename, bulk delete) · **reviewed** 2026-06 (v0.55)

How to restructure a textus store safely.

## Bulk key rename

Rename every leaf key under one prefix to another. UIDs are preserved; one audit row per key.

```sh
textus key mv-prefix old.prefix new.prefix --dry-run   # preview
textus key mv-prefix old.prefix new.prefix             # apply
```

## Bulk delete

Delete every leaf key under a prefix.

```sh
textus key delete-prefix scratch --dry-run
textus key delete-prefix scratch
```

## Rename a lane

Renames the manifest entry and moves the data directory. Refuses if the destination lane already exists.

```sh
textus data mv scratch sandbox --dry-run
textus data mv scratch sandbox
```

## Rename a single key

```sh
textus key mv knowledge.old-name knowledge.new-name
```

## Lint candidate rules

Diff a candidate manifest's `rules:` block against the live manifest before applying. Returns `add_rule` / `remove_rule` / `change_rule` steps. No writes.

```sh
textus rule lint --against=./manifest.candidate.yaml
```

## Schema field rename

Rewrites `_meta` keys in every entry of a given schema family:

```sh
textus schema migrate FAMILY --rename=OLD_FIELD:NEW_FIELD
```
