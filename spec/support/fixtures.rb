RSpec.shared_context "textus_store_fixture" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  after { FileUtils.remove_entry(tmp) }
end

module TextusSpecHelpers
  # Layout-aware paths for specs that assert on runtime artifacts. ADR 0038.
  def audit_log_path(root) = Textus::Layout.audit_log(root)
  def audit_dir_path(root) = Textus::Layout.audit_dir(root)

  # Writes a manifest (+ optional zone dirs, schema files, and seed files)
  # into `textus_dir` and returns the Store. Pair with the
  # "textus_store_fixture" shared context, which provides `root` (the .textus
  # dir) and tmp cleanup, to drop the per-spec build_store/mktmpdir boilerplate:
  #
  #   include_context "textus_store_fixture"
  #   let(:store) { store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML) }
  #     version: textus/3
  #     ...
  #   YAML
  #
  # `schemas` maps name => YAML body (written to schemas/<name>.yaml);
  # `files` maps a path relative to the .textus dir => contents.
  def store_from_manifest(textus_dir, manifest:, lanes: [], schemas: {}, files: {})
    lanes.each { |lane| FileUtils.mkdir_p(File.join(textus_dir, "data", lane)) }
    schemas.each do |name, body|
      FileUtils.mkdir_p(File.join(textus_dir, "schemas"))
      File.write(File.join(textus_dir, "schemas", "#{name}.yaml"), body)
    end
    files.each do |rel, body|
      path = File.join(textus_dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
    end
    File.write(File.join(textus_dir, "manifest.yaml"), manifest)
    Textus::Store.new(textus_dir)
  end

  # Canonical zone name for each kind (ADR 0034; docs/reference/zones.md). The
  # presets name their zone after its kind, so a `kind_zone:` override yields a
  # correctly-named lane (e.g. canon → "knowledge") rather than a mislabeled one.
  LANE_ZONE = {
    "canon" => "knowledge", "workspace" => "notebook", "machine" => "feeds",
    "queue" => "proposals"
  }.freeze

  # Preset: a single canon zone "knowledge" holding one leaf entry. The most
  # common read/write shape. Override `kind_zone:` for machine/queue/workspace;
  # the zone name follows the kind via LANE_ZONE.
  #
  #   let(:store) { minimal_store(root) }                       # knowledge.foo leaf
  #   let(:store) { minimal_store(root, key: "knowledge.doc",   # custom key/path
  #                                     path: "knowledge/doc.md") }
  def minimal_store(root, kind_zone: "canon", lane: LANE_ZONE.fetch(kind_zone), key: "#{lane}.foo", path: "#{lane}/foo.md")
    store_from_manifest(root, lanes: [lane], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: #{lane}, kind: #{kind_zone} }
      entries:
        - { key: #{key}, path: #{path}, lane: #{lane}, kind: leaf }
    YAML
  end

  # Preset: a machine "feeds" zone + a canon "knowledge" zone, each with one
  # leaf. The standard write-path shape (untrusted intake in machine, owned
  # content in canon). Used by put/delete/mv/accept/reject specs.
  def machine_store(root)
    store_from_manifest(root, lanes: %w[feeds knowledge], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: feeds, kind: machine }
        - { name: knowledge, kind: canon }
      entries:
        - { key: feeds.foo, path: data/feeds/foo.md, lane: feeds, kind: leaf }
        - { key: knowledge.bar, path: data/knowledge/bar.md, lane: knowledge, kind: leaf }
    YAML
  end

  # Preset: a machine "feeds" zone with one intake entry (key feeds.doc) wired
  # to a `test_intake` fetch step. Pass the step method body and the source ttl.
  # Optionally pass a `retention:` hash (e.g. `{ ttl: "30d", action: "drop" }`)
  # to add a retention rule; omit for intake-only freshness (ADR 0093).
  # Writes the step class into the store's steps/fetch dir. Defaults to machine; pass
  # `kind_zone: "canon"` for owned-intake — the zone name (and key prefix)
  # follow the kind via LANE_ZONE.
  def intake_store(root, intake_body:, ttl: "1h", retention: nil, kind_zone: "machine")
    zone = LANE_ZONE.fetch(kind_zone)
    manifest = <<~YAML
      version: textus/3
      lanes:
        - { name: #{zone}, kind: #{kind_zone} }
      entries:
        - key: #{zone}.doc
          kind: produced
          path: #{zone}/doc.md
          lane: #{zone}
          source: { from: fetch, handler: test_intake, ttl: #{ttl} }
    YAML
    manifest << "rules:\n  - { match: #{zone}.doc, retention: #{retention} }\n" if retention
    store_from_manifest(
      root,
      lanes: [zone],
      files: {
        "steps/fetch/test_intake.rb" => <<~RUBY,
          class TestIntakeFetch < Textus::Step::Fetch
          #{intake_body}
          end
        RUBY
      },
      manifest: manifest,
    )
  end

  # Builds a Textus::Call value for tests. Callers pass the role (and
  # optionally correlation_id, dry_run) — collaborators come from the
  # Store/Container, not from Call.
  def test_ctx(role: "human", correlation_id: nil, dry_run: false)
    Textus::Call.build(
      role: role, correlation_id: correlation_id, dry_run: dry_run,
    )
  end

  def build_envelope_reader(store)
    Textus::Envelope::Reader.new(
      file_store: store.file_store,
      manifest: store.manifest,
    )
  end

  def build_envelope_writer(store, call, reader: nil)
    Textus::Envelope::Writer.new(
      file_store: store.file_store,
      manifest: store.manifest,
      schemas: store.schemas,
      audit_log: store.audit_log,
      call: call,
      reader: reader || build_envelope_reader(store),
    )
  end

  # The Store builds its Container once at construction; this returns it.
  def fresh_container(store)
    store.container
  end

  # ── Use-case invocation idiom ───────────────────────────────────────────
  # Prefer the public façade for anything reachable through it:
  #
  #   store.as(role, correlation_id:, dry_run:).put("working.foo", meta:, body:)
  #
  # `store.as` reuses the Store's container, whose observe dispatcher is the
  # same object as `store.steps` for pub/sub registration, so in-place
  # `store.steps.register(...)` probes
  # are visible through it.
  #
  # `build_worker` (below) drives an internal use-case class the façade does
  # not expose (Produce::Acquire::Intake). Pass `events:` to swap the bus wholesale
  # (e.g. a recording probe) via the immutable Container's #with.
  def build_worker(store, ctx, steps: nil)
    container = store.container
    container = container.with(steps: steps) if steps
    Textus::Produce::Acquire::Intake.new(container: container, call: ctx)
  end

  # Seed convergence jobs for the given scope and then burn the queue through
  # Maintenance::Drain (which is queue-burn only).
  def converge_now(store, prefix: nil, lane: nil, role: Textus::Role::AUTOMATION) # rubocop:disable Lint/UnusedMethodArgument
    queue = Textus::Ports::JobStore.new(root: store.root)
    Textus::Jobs::Planner.seed(container: store.container, queue: queue, role: role)
    Textus::Jobs::Worker.for(container: store.container, queue: queue).drain
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
