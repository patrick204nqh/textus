module Textus
  module VerbRegistry
    ArgSpec = Data.define(
      :name, :type, :required, :positional, :session_default,
      :description, :wire_name, :default, :source, :coerce, :cli_default
    ) do
      def wire = wire_name || name

      # rubocop:disable Metrics/ParameterLists
      def self.arg(name:, type: String, required: false, positional: false,
                   session_default: nil, description: nil, wire_name: nil,
                   default: nil, source: nil, coerce: nil, cli_default: nil)
        new(name:, type:, required:, positional:, session_default:,
            description:, wire_name:, default:, source:, coerce:, cli_default:)
      end
      # rubocop:enable Metrics/ParameterLists
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
      [ArgSpec.arg(name: :key, required: true, positional: true,
                   description: "dotted entry key to read, e.g. 'knowledge.project'")],
      %i[cli mcp], { default: ->(v, _i) { v&.to_h_for_wire } }, nil, nil, :read
    )

    # ── put ──────────────────────────────────────────────
    register VerbSpec.new(
      :put, "Create or update an entry. Schema-validated. Returns {uid, etag}.",
      [ArgSpec.arg(name: :key, required: true, positional: true,
                   description: "dotted entry key, e.g. 'knowledge.project'; must resolve to a zone the role may write"),
       ArgSpec.arg(name: :meta, type: Hash, wire_name: :_meta,
                   description: "frontmatter; reads back as `_meta`. Schema-validated — call `schema KEY` first"),
       ArgSpec.arg(name: :body,
                   description: "markdown/text payload for md entries; use `content` for json/yaml"),
       ArgSpec.arg(name: :content, type: Hash,
                   description: "structured payload for json/yaml-format entries; omit (use `body`) for markdown entries"),
       ArgSpec.arg(name: :if_etag,
                   description: "optimistic-concurrency guard; write rejected if entry changed since")],
      %i[cli mcp], { default: ->(env, _) { { "uid" => env.uid, "etag" => env.etag } } }, nil, nil, :write
    )

    # ── list ─────────────────────────────────────────────
    register VerbSpec.new(
      :list, "List keys filtered by lane and/or prefix.",
      [ArgSpec.arg(name: :prefix,
                   description: "restrict to keys starting with this dotted prefix, e.g. 'knowledge.runbooks'"),
       ArgSpec.arg(name: :lane,
                   description: "restrict to one lane by name (see `boot` lanes)"),
       ArgSpec.arg(name: :q,
                   description: "full-text search query over entry content (FTS5)"),
       ArgSpec.arg(name: :schema,
                   description: "filter to entries whose schema matches this name")],
      %i[cli mcp], { cli: ->(rows, _) { { "entries" => rows } }, default: identity }, nil, nil, :read
    )

    # ── delete ───────────────────────────────────────────
    register VerbSpec.new(
      :key_delete, "Delete one entry by key. Returns {ok, key, deleted}.",
      [ArgSpec.arg(name: :key, required: true, positional: true,
                   description: "dotted entry key to delete"),
       ArgSpec.arg(name: :if_etag,
                   description: "optimistic-concurrency guard: etag you last read")],
      %i[cli mcp], { default: identity }, "key delete", nil, :write
    )

    # ── move ─────────────────────────────────────────────
    register VerbSpec.new(
      :key_mv, "Rename one entry (same zone + format). Refuses if target exists.",
      [ArgSpec.arg(name: :old_key, required: true, positional: true, description: "current dotted key"),
       ArgSpec.arg(name: :new_key, required: true, positional: true,
                   description: "new dotted key (same zone and format)"),
       ArgSpec.arg(name: :dry_run, type: :boolean,
                   description: "when true, returns planned move without applying")],
      %i[cli mcp], { default: identity }, "key mv", nil, :write
    )

    # ── propose ──────────────────────────────────────────
    register VerbSpec.new(
      :propose, "Write a proposal to the role's propose_lane. Auto-prefixes the key.",
      [ArgSpec.arg(name: :key, required: true, positional: true,
                   description: "key relative to propose_lane, e.g. 'decisions.feature-x'"),
       ArgSpec.arg(name: :meta, type: Hash, wire_name: :_meta,
                   description: "frontmatter. Include a 'proposal:' block naming the target_key"),
       ArgSpec.arg(name: :body,
                   description: "markdown/text payload for markdown-format entries"),
       ArgSpec.arg(name: :content, type: Hash,
                   description: "structured payload for json/yaml-format entries")],
      %i[cli mcp], { default: ->(env, _) { env.to_h_for_wire } }, nil, :json, :write
    )

    # ── accept ───────────────────────────────────────────
    register VerbSpec.new(
      :accept, "Apply a queued proposal to its target zone; requires author.",
      [ArgSpec.arg(name: :pending_key, required: true, positional: true,
                   description: "the queued proposal's key")],
      %i[cli mcp], { default: identity }, "accept", nil, :write
    )

    # ── reject ───────────────────────────────────────────
    register VerbSpec.new(
      :reject, "Discard a queued proposal without applying it.",
      [ArgSpec.arg(name: :pending_key, required: true, positional: true,
                   description: "the queued proposal's key")],
      %i[cli mcp], { default: identity }, "reject", nil, :write
    )

    # ── enqueue ──────────────────────────────────────────
    register VerbSpec.new(
      :enqueue, "Push a registered job type onto the convergence queue.",
      [ArgSpec.arg(name: :type, required: true, positional: true,
                   description: "registered job type (e.g. materialize, re-pull, sweep)"),
       ArgSpec.arg(name: :args, type: Hash, default: {},
                   description: "type-specific arguments (e.g. { key: ... })")],
      %i[cli mcp], { default: identity }, "enqueue", nil, :write
    )

    # ── ingest ───────────────────────────────────────────
    register VerbSpec.new(
      :ingest, "Capture external source material into the raw lane. Write-once.",
      [ArgSpec.arg(name: :kind, required: true, positional: true,
                   description: "source kind: url | file | asset"),
       ArgSpec.arg(name: :slug, required: true,
                   description: "human slug for the key suffix (kebab-case)"),
       ArgSpec.arg(name: :url, description: "remote URL (required when kind=url)"),
       ArgSpec.arg(name: :path,
                   description: "local file path (required when kind=file or kind=asset)"),
       ArgSpec.arg(name: :lane,
                   description: "asset group subdirectory (required when kind=asset)"),
       ArgSpec.arg(name: :label, description: "human label stored in source.label")],
      %i[cli mcp], { default: ->(env, _) { { "key" => env.key, "uid" => env.uid, "etag" => env.etag } } }, nil, nil, :write
    )

    # ── where ────────────────────────────────────────────
    register VerbSpec.new(
      :where, "Resolve a key to its zone, owner, and path without reading the body.",
      [ArgSpec.arg(name: :key, required: true, positional: true, description: "dotted key to locate")],
      %i[cli mcp], { default: identity }, nil, nil, :read
    )

    # ── uid ──────────────────────────────────────────────
    register VerbSpec.new(
      :uid, "Return the stable UID of an entry without reading its body.",
      [ArgSpec.arg(name: :key, required: true, positional: true, description: "entry key")],
      [:cli], { cli: ->(uid, inputs) { { "key" => inputs[:key], "uid" => uid } }, default: identity }, "key uid", nil, :read
    )

    # ── blame ────────────────────────────────────────────
    register VerbSpec.new(
      :blame, "Annotate audit rows with the git commit that introduced each file state.",
      [ArgSpec.arg(name: :key, required: true, positional: true, description: "entry key to blame"),
       ArgSpec.arg(name: :limit, type: Integer,
                   description: "maximum number of audit rows to return")],
      [:cli], {
        cli: ->(rows, inputs) { { "verb" => "blame", "key" => inputs[:key], "rows" => rows } },
        default: identity,
      }, "blame", nil, :read
    )

    # ── audit ────────────────────────────────────────────
    register VerbSpec.new(
      :audit, "Query the audit log with optional filters.",
      [ArgSpec.arg(name: :key, description: "filter to rows for this key"),
       ArgSpec.arg(name: :lane, description: "filter to keys in this lane"),
       ArgSpec.arg(name: :role, description: "filter to rows written under this role"),
       ArgSpec.arg(name: :verb, description: "filter to rows for this verb"),
       ArgSpec.arg(name: :since,
                   description: "ISO-8601 timestamp or relative offset (e.g. 1h, 30m)"),
       ArgSpec.arg(name: :seq_since, type: Integer,
                   description: "return rows with seq > this cursor value"),
       ArgSpec.arg(name: :correlation_id,
                   description: "filter to rows with this correlation_id"),
       ArgSpec.arg(name: :limit, type: Integer,
                   description: "maximum number of rows to return")],
      [:cli], { cli: ->(rows, _) { { "verb" => "audit", "rows" => rows } }, default: identity }, "audit", nil, :read
    )

    # ── deps ─────────────────────────────────────────────
    register VerbSpec.new(
      :deps, "List the keys a derived entry depends on.",
      [ArgSpec.arg(name: :key, required: true, positional: true,
                   description: "dotted key of the derived entry whose source keys you want")],
      %i[cli mcp], { default: identity }, nil, nil, :read
    )

    # ── rdeps ────────────────────────────────────────────
    register VerbSpec.new(
      :rdeps, "List the derived entries that depend on a key (reverse deps).",
      [ArgSpec.arg(name: :key, required: true, positional: true,
                   description: "dotted key whose dependents you want")],
      %i[cli mcp], { default: identity }, nil, nil, :read
    )

    # ── pulse ────────────────────────────────────────────
    register VerbSpec.new(
      :pulse, "Delta since cursor — changed entries, pending proposals, index freshness.",
      [ArgSpec.arg(name: :since, type: Integer, session_default: :cursor,
                   description: "audit seq to diff from; defaults to the session cursor")],
      %i[cli mcp], { default: identity }, nil, nil, :read
    )

    # ── rule_explain ─────────────────────────────────────
    register VerbSpec.new(
      :rule_explain, "Effective rules for a key. Lean by default; detail: true adds matched blocks.",
      [ArgSpec.arg(name: :key, required: true, positional: true,
                   description: "dotted key whose effective rules you want"),
       ArgSpec.arg(name: :detail, type: :boolean,
                   description: "detail: true adds matched blocks + guard predicates")],
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
      [ArgSpec.arg(name: :key, required: true, positional: true,
                   description: "any key in the family whose schema you want")],
      %i[cli mcp], { default: identity }, "schema show", nil, :read
    )

    # ── doctor ───────────────────────────────────────────
    register VerbSpec.new(
      :doctor, "Run health checks on the textus store.",
      [ArgSpec.arg(name: :checks, type: Array,
                   description: "subset of check names to run (default: all)")],
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
      [ArgSpec.arg(name: :state, default: "ready",
                   description: "ready|leased|done|failed"),
       ArgSpec.arg(name: :action, description: "retry|purge (optional)"),
       ArgSpec.arg(name: :job_id, description: "job id (required for action=retry)")],
      %i[cli mcp], { default: identity }, "jobs", nil, :read
    )

    # ── data_mv ──────────────────────────────────────────
    register VerbSpec.new(
      :data_mv, "Rename a data lane — manifest + files. Refuses if destination exists.",
      [ArgSpec.arg(name: :from, required: true, positional: true, description: "current data lane name"),
       ArgSpec.arg(name: :to, required: true, positional: true, description: "new data lane name"),
       ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                   description: "when true, returns planned zone move without applying")],
      %i[cli mcp], { default: ->(v, _) { v.to_h } }, "data mv", nil, :write
    )

    # ── key_mv_prefix ────────────────────────────────────
    register VerbSpec.new(
      :key_mv_prefix, "Bulk-rename every leaf key under from_prefix to to_prefix.",
      [ArgSpec.arg(name: :from_prefix, required: true, positional: true,
                   description: "dotted prefix whose leaf keys are renamed"),
       ArgSpec.arg(name: :to_prefix, required: true, positional: true,
                   description: "dotted prefix the keys are renamed to"),
       ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                   description: "when true, returns planned moves without applying")],
      %i[cli mcp], { default: ->(v, _) { v.to_h } }, "key mv-prefix", nil, :write
    )

    # ── key_delete_prefix ────────────────────────────────
    register VerbSpec.new(
      :key_delete_prefix, "Bulk-delete every leaf key under prefix.",
      [ArgSpec.arg(name: :prefix, required: true, positional: true,
                   description: "every leaf key under this dotted prefix is deleted"),
       ArgSpec.arg(name: :dry_run, type: :boolean, default: false,
                   description: "when true, returns keys that would be deleted without deleting")],
      %i[cli mcp], { default: ->(v, _) { v.to_h } }, "key delete-prefix", nil, :write
    )

    # ── drain ────────────────────────────────────────────
    register VerbSpec.new(
      :drain, "Seed materialize + sweep jobs then drain the queue to empty.",
      [ArgSpec.arg(name: :prefix, description: "restrict to keys under this dotted prefix"),
       ArgSpec.arg(name: :lane, description: "restrict to entries in this lane")],
      %i[cli mcp], { default: identity }, nil, nil, :maintenance
    )

    # ── rule_lint ────────────────────────────────────────
    register VerbSpec.new(
      :rule_lint, "Diff candidate manifest rules against the live manifest.",
      [ArgSpec.arg(name: :candidate_yaml, required: true,
                   wire_name: :against, source: :file,
                   description: "path to candidate manifest YAML")],
      %i[cli mcp], { default: ->(v, _) { v.to_h } }, "rule lint", nil, :maintenance
    )
  end
end

# Generate explicit methods on Store for each registered verb so the API
# is statically discoverable by IDEs and documentation tools.
Textus::Store.class_eval do
  Textus::VerbRegistry::VERBS.each do |verb, spec|
    positional_names = Textus::VerbRegistry::POSITIONAL[verb] || []
    define_method(verb) do |*args, **kwargs|
      if args.size > positional_names.size
        raise ArgumentError.new("#{verb} accepts #{positional_names.size} positional argument(s) (got #{args.size})")
      end

      positional_inputs = positional_names.zip(args).to_h.compact
      inputs = positional_inputs.merge(kwargs)
      pending = Textus::Dispatch::Binder.command(spec, inputs)
      call    = Textus::Value::Call.build(role: @role, correlation_id: @correlation_id)
      result  = @container.pipeline.dispatch(pending, call: call)
      Textus::Value::Result.extract(result)
    end
  end
end
