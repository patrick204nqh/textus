module Textus
  module VerbRegistry
    ArgSpec = Data.define(
      :name, :type, :required, :positional, :session_default,
      :description, :wire_name, :default, :source, :coerce, :cli_default
    ) do
      def wire = wire_name || name
    end

    TYPE_MAP = {
      String => "string", Integer => "integer", Hash => "object",
      Array => "array", :boolean => "boolean"
    }.freeze

    VerbSpec = Data.define(:verb, :summary, :args, :surfaces, :views, :cli, :cli_stdin, :category) do
      def mcp? = surfaces.include?(:mcp)
      def cli? = surfaces.include?(:cli)
      def view(surface = :default) = views[surface] || views.fetch(:default)
      def cli_path = cli || verb.to_s
      def cli_words = cli_path.split
      def cli_group = cli_words.size > 1 ? cli_words.first : nil
      def cli_leaf  = cli_words.last
      def required_args = args.select(&:required)
      def read? = category == :read
      def write? = category == :write
      def maintenance? = category == :maintenance

      def input_schema
        props = args.to_h do |a|
          json_type = VerbRegistry::TYPE_MAP[a.type] || "string"
          h = { "type" => json_type }
          h["description"] = a.description if a.description
          [a.wire.to_s, h]
        end
        { type: "object", properties: props, required: required_args.map { |a| a.wire.to_s } }
      end
    end

    VERBS = {}
    POSITIONAL = {}

    def self.register(spec)
      VERBS[spec.verb] = spec
      POSITIONAL[spec.verb] = spec.args.select(&:positional).map(&:name)
    end

    def self.for(verb) = VERBS[verb]
    def self.positional_for(verb) = POSITIONAL[verb] || []
    def self.summary_for(verb) = VERBS[verb]&.summary
    def self.registered = VERBS.values
    def self.contract_class_for(verb) = VERB_TO_CONTRACT[verb]

    VERB_TO_CONTRACT = {
      get: Dispatch::Contracts::GetEntry,
      put: Dispatch::Contracts::PutEntry,
      list: Dispatch::Contracts::ListKeys,
      key_delete: Dispatch::Contracts::DeleteKey,
      key_mv: Dispatch::Contracts::MoveKey,
      propose: Dispatch::Contracts::ProposeEntry,
      accept: Dispatch::Contracts::AcceptProposal,
      reject: Dispatch::Contracts::RejectProposal,
      enqueue: Dispatch::Contracts::EnqueueJob,
      audit: Dispatch::Contracts::AuditEntries,
      pulse: Dispatch::Contracts::PulseEntries,
      blame: Dispatch::Contracts::BlameEntry,
      where: Dispatch::Contracts::WhereEntry,
      uid: Dispatch::Contracts::UidEntry,
      deps: Dispatch::Contracts::DepsEntry,
      rdeps: Dispatch::Contracts::RdepsEntry,
      boot: Dispatch::Contracts::BootStore,
      doctor: Dispatch::Contracts::DoctorStore,
      published: Dispatch::Contracts::PublishedEntries,
      rule_explain: Dispatch::Contracts::RuleExplain,
      rule_list: Dispatch::Contracts::RuleList,
      schema_show: Dispatch::Contracts::SchemaEnvelope,
      drain: Dispatch::Contracts::DrainStore,
      ingest: Dispatch::Contracts::IngestEntry,
      jobs: Dispatch::Contracts::JobsAction,
      rule_lint: Dispatch::Contracts::RuleLint,
      data_mv: Dispatch::Contracts::DataMv,
      key_mv_prefix: Dispatch::Contracts::KeyMvPrefix,
      key_delete_prefix: Dispatch::Contracts::KeyDeletePrefix,
    }.freeze

    CONTRACT_TO_VERB = VERB_TO_CONTRACT.invert.freeze

    private_constant :VERB_TO_CONTRACT, :CONTRACT_TO_VERB

    def self.contract_to_verb(klass)
      CONTRACT_TO_VERB[klass] || klass.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end

    def self.contract_to_verb!(klass)
      CONTRACT_TO_VERB.fetch(klass) { raise "unknown contract class: #{klass}" }
    end

    identity = ->(v, _) { v }

    # ── get ──────────────────────────────────────────────
    register VerbSpec.new(
      :get, "Read one entry — on-disk read with freshness verdict.",
      [ArgSpec[:key, String, true, true, nil,
               "dotted entry key to read, e.g. 'knowledge.project'", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: ->(v, _i) { v&.to_h_for_wire } }, nil, nil, :read
    )

    # ── put ──────────────────────────────────────────────
    register VerbSpec.new(
      :put, "Create or update an entry. Schema-validated. Returns {uid, etag}.",
      [ArgSpec[:key, String, true, true, nil,
               "dotted entry key, e.g. 'knowledge.project'; must resolve to a zone the role may write", nil, nil, nil, nil, :__unset],
       ArgSpec[:meta, Hash, false, false, nil,
               "frontmatter; reads back as `_meta`. Schema-validated — call `schema KEY` first", :_meta, nil, nil, nil, :__unset],
       ArgSpec[:body, String, false, false, nil,
               "markdown/text payload for md entries; use `content` for json/yaml", nil, nil, nil, nil, :__unset],
       ArgSpec[:content, Hash, false, false, nil,
               "structured payload for json/yaml-format entries; omit (use `body`) for markdown entries", nil, nil, nil, nil, :__unset],
       ArgSpec[:if_etag, String, false, false, nil,
               "optimistic-concurrency guard; write rejected if entry changed since", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: ->(env, _) { { "uid" => env.uid, "etag" => env.etag } } }, nil, nil, :write
    )

    # ── list ─────────────────────────────────────────────
    register VerbSpec.new(
      :list, "List keys filtered by lane and/or prefix.",
      [ArgSpec[:prefix, String, false, false, nil,
               "restrict to keys starting with this dotted prefix, e.g. 'knowledge.runbooks'", nil, nil, nil, nil, :__unset],
       ArgSpec[:lane, String, false, false, nil,
               "restrict to one lane by name (see `boot` lanes)", nil, nil, nil, nil, :__unset],
       ArgSpec[:q, String, false, false, nil,
               "full-text search query over entry content (FTS5)", nil, nil, nil, nil, :__unset],
       ArgSpec[:schema, String, false, false, nil,
               "filter to entries whose schema matches this name", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { cli: ->(rows, _) { { "entries" => rows } }, default: identity }, nil, nil, :read
    )

    # ── delete ───────────────────────────────────────────
    register VerbSpec.new(
      :key_delete, "Delete one entry by key. Returns {ok, key, deleted}.",
      [ArgSpec[:key, String, true, true, nil,
               "dotted entry key to delete", nil, nil, nil, nil, :__unset],
       ArgSpec[:if_etag, String, false, false, nil,
               "optimistic-concurrency guard: etag you last read", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, "key delete", nil, :write
    )

    # ── move ─────────────────────────────────────────────
    register VerbSpec.new(
      :key_mv, "Rename one entry (same zone + format). Refuses if target exists.",
      [ArgSpec[:old_key, String, true, true, nil,
               "current dotted key", nil, nil, nil, nil, :__unset],
       ArgSpec[:new_key, String, true, true, nil,
               "new dotted key (same zone and format)", nil, nil, nil, nil, :__unset],
       ArgSpec[:dry_run, :boolean, false, false, nil,
               "when true, returns planned move without applying", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, "key mv", nil, :write
    )

    # ── propose ──────────────────────────────────────────
    register VerbSpec.new(
      :propose, "Write a proposal to the role's propose_lane. Auto-prefixes the key.",
      [ArgSpec[:key, String, true, true, nil,
               "key relative to propose_lane, e.g. 'decisions.feature-x'", nil, nil, nil, nil, :__unset],
       ArgSpec[:meta, Hash, false, false, nil,
               "frontmatter. Include a 'proposal:' block naming the target_key", :_meta, nil, nil, nil, :__unset],
       ArgSpec[:body, String, false, false, nil,
               "markdown/text payload for markdown-format entries", nil, nil, nil, nil, :__unset],
       ArgSpec[:content, Hash, false, false, nil,
               "structured payload for json/yaml-format entries", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: ->(env, _) { env.to_h_for_wire } }, nil, :json, :write
    )

    # ── accept ───────────────────────────────────────────
    register VerbSpec.new(
      :accept, "Apply a queued proposal to its target zone; requires author.",
      [ArgSpec[:pending_key, String, true, true, nil,
               "the queued proposal's key", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, "accept", nil, :write
    )

    # ── reject ───────────────────────────────────────────
    register VerbSpec.new(
      :reject, "Discard a queued proposal without applying it.",
      [ArgSpec[:pending_key, String, true, true, nil,
               "the queued proposal's key", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, "reject", nil, :write
    )

    # ── enqueue ──────────────────────────────────────────
    register VerbSpec.new(
      :enqueue, "Push a registered job type onto the convergence queue.",
      [ArgSpec[:type, String, true, true, nil,
               "registered job type (e.g. materialize, re-pull, sweep)", nil, nil, nil, nil, :__unset],
       ArgSpec[:args, Hash, false, false, nil,
               "type-specific arguments (e.g. { key: ... })", nil, {}, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, "enqueue", nil, :write
    )

    # ── ingest ───────────────────────────────────────────
    register VerbSpec.new(
      :ingest, "Capture external source material into the raw lane. Write-once.",
      [ArgSpec[:kind, String, true, true, nil,
               "source kind: url | file | asset", nil, nil, nil, nil, :__unset],
       ArgSpec[:slug, String, true, false, nil,
               "human slug for the key suffix (kebab-case)", nil, nil, nil, nil, :__unset],
       ArgSpec[:url, String, false, false, nil,
               "remote URL (required when kind=url)", nil, nil, nil, nil, :__unset],
       ArgSpec[:path, String, false, false, nil,
               "local file path (required when kind=file or kind=asset)", nil, nil, nil, nil, :__unset],
       ArgSpec[:lane, String, false, false, nil,
               "asset group subdirectory (required when kind=asset)", nil, nil, nil, nil, :__unset],
       ArgSpec[:label, String, false, false, nil,
               "human label stored in source.label", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: ->(env, _) { { "key" => env.key, "uid" => env.uid, "etag" => env.etag } } }, nil, nil, :write
    )

    # ── where ────────────────────────────────────────────
    register VerbSpec.new(
      :where, "Resolve a key to its zone, owner, and path without reading the body.",
      [ArgSpec[:key, String, true, true, nil,
               "dotted key to locate", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, nil, nil, :read
    )

    # ── uid ──────────────────────────────────────────────
    register VerbSpec.new(
      :uid, "Return the stable UID of an entry without reading its body.",
      [ArgSpec[:key, String, true, true, nil,
               "entry key", nil, nil, nil, nil, :__unset]],
      [:cli], { cli: ->(uid, inputs) { { "key" => inputs[:key], "uid" => uid } }, default: identity }, "key uid", nil, :read
    )

    # ── blame ────────────────────────────────────────────
    register VerbSpec.new(
      :blame, "Annotate audit rows with the git commit that introduced each file state.",
      [ArgSpec[:key, String, true, true, nil,
               "entry key to blame", nil, nil, nil, nil, :__unset],
       ArgSpec[:limit, Integer, false, false, nil,
               "maximum number of audit rows to return", nil, nil, nil, nil, :__unset]],
      [:cli], {
        cli: ->(rows, inputs) { { "verb" => "blame", "key" => inputs[:key], "rows" => rows } },
        default: identity,
      }, "blame", nil, :read
    )

    # ── audit ────────────────────────────────────────────
    register VerbSpec.new(
      :audit, "Query the audit log with optional filters.",
      [ArgSpec[:key, String, false, false, nil, "filter to rows for this key", nil, nil, nil, nil, :__unset],
       ArgSpec[:lane, String, false, false, nil, "filter to keys in this lane", nil, nil, nil, nil, :__unset],
       ArgSpec[:role, String, false, false, nil, "filter to rows written under this role", nil, nil, nil, nil, :__unset],
       ArgSpec[:verb, String, false, false, nil, "filter to rows for this verb", nil, nil, nil, nil, :__unset],
       ArgSpec[:since, String, false, false, nil,
               "ISO-8601 timestamp or relative offset (e.g. 1h, 30m)", nil, nil, nil, nil, :__unset],
       ArgSpec[:seq_since, Integer, false, false, nil,
               "return rows with seq > this cursor value", nil, nil, nil, nil, :__unset],
       ArgSpec[:correlation_id, String, false, false, nil,
               "filter to rows with this correlation_id", nil, nil, nil, nil, :__unset],
       ArgSpec[:limit, Integer, false, false, nil,
               "maximum number of rows to return", nil, nil, nil, nil, :__unset]],
      [:cli], { cli: ->(rows, _) { { "verb" => "audit", "rows" => rows } }, default: identity }, "audit", nil, :read
    )

    # ── deps ─────────────────────────────────────────────
    register VerbSpec.new(
      :deps, "List the keys a derived entry depends on.",
      [ArgSpec[:key, String, true, true, nil,
               "dotted key of the derived entry whose source keys you want", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, nil, nil, :read
    )

    # ── rdeps ────────────────────────────────────────────
    register VerbSpec.new(
      :rdeps, "List the derived entries that depend on a key (reverse deps).",
      [ArgSpec[:key, String, true, true, nil,
               "dotted key whose dependents you want", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, nil, nil, :read
    )

    # ── pulse ────────────────────────────────────────────
    register VerbSpec.new(
      :pulse, "Delta since cursor — changed entries, pending proposals, index freshness.",
      [ArgSpec[:since, Integer, false, false, :cursor,
               "audit seq to diff from; defaults to the session cursor", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, nil, nil, :read
    )

    # ── rule_explain ─────────────────────────────────────
    register VerbSpec.new(
      :rule_explain, "Effective rules for a key. Lean by default; detail: true adds matched blocks.",
      [ArgSpec[:key, String, true, true, nil,
               "dotted key whose effective rules you want", nil, nil, nil, nil, :__unset],
       ArgSpec[:detail, :boolean, false, false, nil,
               "detail: true adds matched blocks + guard predicates", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], {
        cli: ->(r, _) { { "verb" => "rule_explain" }.merge(r.transform_keys(&:to_s)) },
        default: identity,
      }, "rule explain", nil, :read
    )

    # ── rule_list ────────────────────────────────────────
    register VerbSpec.new(
      :rule_list, "List every rule block in the manifest.",
      [], [:cli], { cli: ->(p, _) { { "verb" => "rule_list", "policies" => p } }, default: identity }, "rule list", nil, :read
    )

    # ── published ────────────────────────────────────────
    register VerbSpec.new(
      :published, "List all entries that declare a publish target.",
      [], [:cli], { default: identity }, "published", nil, :read
    )

    # ── schema_show ──────────────────────────────────────
    register VerbSpec.new(
      :schema_show, "Return the schema (field shape) for an entry's family.",
      [ArgSpec[:key, String, true, true, nil,
               "any key in the family whose schema you want", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, "schema show", nil, :read
    )

    # ── doctor ───────────────────────────────────────────
    register VerbSpec.new(
      :doctor, "Run health checks on the textus store.",
      [ArgSpec[:checks, Array, false, false, nil,
               "subset of check names to run (default: all)", nil, nil, nil, nil, :__unset]],
      [:cli], { default: identity }, "doctor", nil, :read
    )

    # ── boot ─────────────────────────────────────────────
    register VerbSpec.new(
      :boot, "Return the orientation contract: lanes, agent_quickstart, agent_protocol.",
      [], %i[cli mcp], { default: identity }, nil, nil, :read
    )

    # ── jobs ─────────────────────────────────────────────
    register VerbSpec.new(
      :jobs, "List queued jobs by state; retry a dead-lettered job or purge.",
      [ArgSpec[:state, String, false, false, nil,
               "ready|leased|done|failed", nil, "ready", nil, nil, :__unset],
       ArgSpec[:action, String, false, false, nil,
               "retry|purge (optional)", nil, nil, nil, nil, :__unset],
       ArgSpec[:job_id, String, false, false, nil,
               "job id (required for action=retry)", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, "jobs", nil, :read
    )

    # ── data_mv ──────────────────────────────────────────
    register VerbSpec.new(
      :data_mv, "Rename a data lane — manifest + files. Refuses if destination exists.",
      [ArgSpec[:from, String, true, true, nil,
               "current data lane name", nil, nil, nil, nil, :__unset],
       ArgSpec[:to, String, true, true, nil,
               "new data lane name", nil, nil, nil, nil, :__unset],
       ArgSpec[:dry_run, :boolean, false, false, nil,
               "when true, returns planned zone move without applying", nil, false, nil, nil, :__unset]],
      %i[cli mcp], { default: ->(v, _) { v.to_h } }, "data mv", nil, :write
    )

    # ── key_mv_prefix ────────────────────────────────────
    register VerbSpec.new(
      :key_mv_prefix, "Bulk-rename every leaf key under from_prefix to to_prefix.",
      [ArgSpec[:from_prefix, String, true, true, nil,
               "dotted prefix whose leaf keys are renamed", nil, nil, nil, nil, :__unset],
       ArgSpec[:to_prefix, String, true, true, nil,
               "dotted prefix the keys are renamed to", nil, nil, nil, nil, :__unset],
       ArgSpec[:dry_run, :boolean, false, false, nil,
               "when true, returns planned moves without applying", nil, false, nil, nil, :__unset]],
      %i[cli mcp], { default: ->(v, _) { v.to_h } }, "key mv-prefix", nil, :write
    )

    # ── key_delete_prefix ────────────────────────────────
    register VerbSpec.new(
      :key_delete_prefix, "Bulk-delete every leaf key under prefix.",
      [ArgSpec[:prefix, String, true, true, nil,
               "every leaf key under this dotted prefix is deleted", nil, nil, nil, nil, :__unset],
       ArgSpec[:dry_run, :boolean, false, false, nil,
               "when true, returns keys that would be deleted without deleting", nil, false, nil, nil, :__unset]],
      %i[cli mcp], { default: ->(v, _) { v.to_h } }, "key delete-prefix", nil, :write
    )

    # ── drain ────────────────────────────────────────────
    register VerbSpec.new(
      :drain, "Seed materialize + sweep jobs then drain the queue to empty.",
      [ArgSpec[:prefix, String, false, false, nil,
               "restrict to keys under this dotted prefix", nil, nil, nil, nil, :__unset],
       ArgSpec[:lane, String, false, false, nil,
               "restrict to entries in this lane", nil, nil, nil, nil, :__unset]],
      %i[cli mcp], { default: identity }, nil, nil, :maintenance
    )

    # ── rule_lint ────────────────────────────────────────
    register VerbSpec.new(
      :rule_lint, "Diff candidate manifest rules against the live manifest.",
      [ArgSpec[:candidate_yaml, String, true, false, nil,
               "path to candidate manifest YAML", :against, nil, :file, nil, :__unset]],
      %i[cli mcp], { default: ->(v, _) { v.to_h } }, "rule lint", nil, :maintenance
    )
  end
end
