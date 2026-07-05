# frozen_string_literal: true

module Textus
  module Protocol
    module VerbRegistry
      CoreVerbs = {
        audit: VerbSpec.new(
          :audit, "Query the audit log with optional filters.",
          [ArgSpec.arg(name: :key, description: "filter to rows for this key"),
           ArgSpec.arg(name: :lane, description: "filter to keys in this lane"),
           ArgSpec.arg(name: :role, description: "filter to rows written under this role"),
           ArgSpec.arg(name: :verb, description: "filter to rows for this verb"),
           ArgSpec.arg(name: :since, description: "ISO-8601 timestamp or relative offset (e.g. 1h, 30m)"),
           ArgSpec.arg(name: :seq_since, type: Integer, description: "return rows with seq > this cursor value"),
           ArgSpec.arg(name: :correlation_id, description: "filter to rows with this correlation_id"),
           ArgSpec.arg(name: :limit, type: Integer, description: "maximum number of rows to return")],
          %i[cli mcp], :read
        ),

        blame: VerbSpec.new(
          :blame, "Annotate audit rows with the git commit that introduced each file state.",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "entry key to blame"),
           ArgSpec.arg(name: :limit, type: Integer, description: "maximum number of audit rows to return")],
          %i[cli mcp], :read
        ),

        boot: VerbSpec.new(
          :boot, "Return the orientation contract: lanes, agent_quickstart, agent_protocol.",
          [], %i[cli mcp], :read
        ),

        data_mv: VerbSpec.new(
          :data_mv, "Rename a data lane — manifest + files. Refuses if destination exists.",
          [ArgSpec.arg(name: :from, required: true, positional: true, description: "current data lane name"),
           ArgSpec.arg(name: :to, required: true, positional: true, description: "new data lane name"),
           ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                       description: "when true, returns planned zone move without applying")],
          %i[cli mcp], :write
        ),

        deps: VerbSpec.new(
          :deps, "List the keys a derived entry depends on.",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "dotted key of the derived entry whose source keys you want")],
          %i[cli mcp], :read
        ),

        drain: VerbSpec.new(
          :drain, "Seed materialize + sweep jobs then drain the queue to empty.",
          [], %i[cli mcp], :maintenance
        ),

        get: VerbSpec.new(
          :get, "Read one entry — on-disk read with freshness verdict.",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "dotted entry key to read, e.g. 'knowledge.project'")],
          %i[cli mcp], :read
        ),

        graph: VerbSpec.new(
          :graph, "Query the link graph — neighbors (direct links) or reachable (transitive, with optional depth limit).",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "entry key to query"),
           ArgSpec.arg(name: :depth, type: Integer, description: "max traversal depth for reachable query (unlimited when omitted)")],
          %i[cli mcp], :read
        ),

        ingest: VerbSpec.new(
          verb: :ingest, summary: "Capture external source material into the raw lane. Write-once.",
          args: [ArgSpec.arg(name: :kind, required: true, positional: true, description: "source kind: url | file | asset"),
                 ArgSpec.arg(name: :slug, required: true, description: "human slug for the key suffix (kebab-case)"),
                 ArgSpec.arg(name: :url, description: "remote URL (required when kind=url)"),
                 ArgSpec.arg(name: :path, description: "local file path (required when kind=file or kind=asset)"),
                 ArgSpec.arg(name: :lane, description: "asset group subdirectory (required when kind=asset)"),
                 ArgSpec.arg(name: :label, description: "human label stored in source.label")],
          surfaces: %i[cli mcp], category: :write, lane: :ingest
        ),

        key_delete: VerbSpec.new(
          :key_delete, "Delete one entry by key. Returns {ok, key, deleted}.",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "dotted entry key to delete"),
           ArgSpec.arg(name: :if_etag, description: "optimistic-concurrency guard: etag you last read")],
          %i[cli mcp], :write
        ),

        key_delete_prefix: VerbSpec.new(
          :key_delete_prefix, "Bulk-delete every leaf key under prefix.",
          [ArgSpec.arg(name: :prefix, required: true, positional: true, description: "every leaf key under this dotted prefix is deleted"),
           ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                       description: "when true, returns keys that would be deleted without deleting")],
          %i[cli mcp], :write
        ),

        key_mv: VerbSpec.new(
          :key_mv, "Rename one entry (same zone + format). Refuses if target exists.",
          [ArgSpec.arg(name: :old_key, required: true, positional: true, description: "current dotted key"),
           ArgSpec.arg(name: :new_key, required: true, positional: true, description: "new dotted key (same zone and format)"),
           ArgSpec.arg(name: :dry_run, type: :boolean, description: "when true, returns planned move without applying")],
          %i[cli mcp], :write
        ),

        key_mv_prefix: VerbSpec.new(
          :key_mv_prefix, "Bulk-rename every leaf key under from_prefix to to_prefix.",
          [ArgSpec.arg(name: :from_prefix, required: true, positional: true, description: "dotted prefix whose leaf keys are renamed"),
           ArgSpec.arg(name: :to_prefix, required: true, positional: true, description: "dotted prefix the keys are renamed to"),
           ArgSpec.arg(name: :dry_run, type: :boolean, default: false, description: "when true, returns planned moves without applying")],
          %i[cli mcp], :write
        ),

        list: VerbSpec.new(
          :list, "List keys filtered by lane and/or prefix.",
          [ArgSpec.arg(name: :prefix, description: "restrict to keys starting with this dotted prefix, e.g. 'knowledge.execution'"),
           ArgSpec.arg(name: :lane, description: "restrict to one lane by name (see `boot` lanes)"),
           ArgSpec.arg(name: :q, description: "full-text search query over entry content (FTS5)"),
           ArgSpec.arg(name: :schema, description: "filter to entries whose schema matches this name")],
          %i[cli mcp], :read
        ),

        pulse: VerbSpec.new(
          :pulse, "Delta since cursor — changed entries, pending proposals, index freshness.",
          [ArgSpec.arg(name: :since, type: Integer, description: "audit seq to diff from; defaults to the session cursor")],
          %i[cli mcp], :read
        ),

        put: VerbSpec.new(
          :put, "Create or update an entry. Schema-validated. Returns {uid, etag}.",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "dotted entry key, e.g. 'knowledge.project'; must resolve to a zone the role may write"),
           ArgSpec.arg(name: :meta, type: Hash, wire_name: :_meta,
                       description: "frontmatter; reads back as `_meta`. Schema-validated — call `schema KEY` first"),
           ArgSpec.arg(name: :body, description: "markdown/text payload for md entries; use `content` for json/yaml"),
           ArgSpec.arg(name: :content, type: Hash,
                       description: "structured payload for json/yaml-format entries; omit (use `body`) for markdown entries"),
           ArgSpec.arg(name: :if_etag, description: "optimistic-concurrency guard; write rejected if entry changed since"),
           ArgSpec.arg(name: :format, description: "override entry format for this write (e.g. script)")],
          %i[cli mcp], :write
        ),

        rdeps: VerbSpec.new(
          :rdeps, "List the derived entries that depend on a key (reverse deps).",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "dotted key whose dependents you want")],
          %i[cli mcp], :read
        ),

        schema_list: VerbSpec.new(
          :schema_list, "List all registered schemas with their fields.",
          [], %i[cli mcp], :read
        ),

        schema_show: VerbSpec.new(
          :schema_show, "Return the schema (field shape) for an entry's family.",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "any key in the family whose schema you want")],
          %i[cli mcp], :read
        ),

        uid: VerbSpec.new(
          :uid, "Return the stable UID of an entry without reading its body.",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "entry key")],
          %i[cli mcp], :read
        ),

        where: VerbSpec.new(
          :where, "Resolve a key to its zone, owner, and path without reading the body.",
          [ArgSpec.arg(name: :key, required: true, positional: true, description: "dotted key to locate")],
          %i[cli mcp], :read
        ),
      }.freeze
    end
  end
end
