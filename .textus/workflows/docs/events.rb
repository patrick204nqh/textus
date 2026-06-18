EVENTS_CATALOG = [
  {
    "name" => "resolve_handler",
    "mode" => "rpc",
    "desc" => "Fetch bytes into an `intake` entry (`source: { from: handler }`). " \
              "Invoked by `textus drain` and `hook run` when re-pulling past `source.ttl`; never by a `get` (ADR 0089).",
  },
  {
    "name" => "transform_rows",
    "mode" => "rpc",
    "desc" => "Reshape projection rows for a produced entry (`source: { from: project }`) — " \
              "shapes the **data**, not its presentation. Invoked by `textus drain` (Phase 1 produce).",
  },
  {
    "name" => "validate",
    "mode" => "rpc",
    "desc" => "Contribute a custom rule to `textus doctor`. Returns an array of issues.",
  },
  {
    "name" => "entry_written",
    "mode" => "pubsub",
    "desc" => "Something just got written. Fires for every successful write (including fetch-driven). " \
              "Payload: `{ ctx:, key:, envelope: }`.",
  },
  {
    "name" => "entry_deleted",
    "mode" => "pubsub",
    "desc" => "An entry was just unlinked. Payload: `{ ctx:, key: }`.",
  },
  {
    "name" => "entry_fetched",
    "mode" => "pubsub",
    "desc" => "Like `:entry_written` but specific to fetch-driven writes. Both fire — `:entry_written` first, " \
              "then `:entry_fetched`. Payload: `{ ctx:, key:, envelope:, change: }`.",
  },
  {
    "name" => "entry_produced",
    "mode" => "pubsub",
    "desc" => "One produced entry just finished building its data. Fires once per produced entry per drain. " \
              "Payload: `{ ctx:, key:, envelope:, sources: }`.",
  },
  {
    "name" => "proposal_accepted",
    "mode" => "pubsub",
    "desc" => "A pending proposal was promoted into its target zone. Payload: `{ ctx:, key:, target_key: }`.",
  },
  {
    "name" => "entry_published",
    "mode" => "pubsub",
    "desc" => "A produced entry's data was emitted to a repo path. Fires once per file for every publish " \
              "target. Payload: `{ ctx:, key:, envelope:, source:, target: }`.",
  },
  {
    "name" => "entry_renamed",
    "mode" => "pubsub",
    "desc" => "A key was renamed in place. `:entry_written` and `:entry_deleted` are suppressed — " \
              "`:entry_renamed` is the sole signal. Payload: `{ ctx:, key:, from_key:, to_key:, envelope: }`. " \
              "`key:` equals `to_key:`.",
  },
  {
    "name" => "proposal_rejected",
    "mode" => "pubsub",
    "desc" => "A pending proposal was explicitly discarded. Counterpart to `:proposal_accepted`. " \
              "Payload: `{ ctx:, key:, target_key: }`.",
  },
  {
    "name" => "store_loaded",
    "mode" => "pubsub",
    "desc" => "Fires exactly once after `Store#initialize` finishes — hooks are registered, ports are wired. " \
              "Use for cache warmups or external watcher registration. Payload: `{ ctx: }`.",
  },
  {
    "name" => "session_opened",
    "mode" => "pubsub",
    "desc" => "Fires when an MCP session is established. Payload: `{ ctx:, role:, cursor: }`.",
  },
  {
    "name" => "produce_failed",
    "mode" => "pubsub",
    "desc" => "Fires when a **reactive** rebuild raises. Payload: `{ ctx:, keys:, error: }`. " \
              "Observational; the failing rebuild is already aborted.",
  },
].freeze

FETCH_EVENTS_CATALOG = [
  {
    "name" => "entry_fetch_started",
    "mode" => "pubsub",
    "desc" => "Fires immediately before an intake handler is invoked for a re-pull. " \
              "`mode:` is `\"refresh\"`. Payload: `{ ctx:, key:, mode: }`.",
  },
  {
    "name" => "entry_fetch_failed",
    "mode" => "pubsub",
    "desc" => "Fires when an intake handler raises. Payload: `{ ctx:, key:, error_class:, error_message: }`. " \
              "The failing fetch is already aborted; this is observational only.",
  },
].freeze

Textus.workflow "events" do
  match "artifacts.events"

  step :build do |_, _ctx|
    all = EVENTS_CATALOG + FETCH_EVENTS_CATALOG
    { "content" => {
      "events" => EVENTS_CATALOG,
      "fetch_events" => FETCH_EVENTS_CATALOG,
      "total_count" => all.size,
      "rpc_count" => all.count { |e| e["mode"] == "rpc" },
      "pubsub_count" => all.count { |e| e["mode"] == "pubsub" },
    } }
  end

  publish
end
