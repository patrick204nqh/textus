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
  #   let(:store) { store_from_manifest(root, zones: %w[knowledge], manifest: <<~YAML) }
  #     version: textus/3
  #     ...
  #   YAML
  #
  # `schemas` maps name => YAML body (written to schemas/<name>.yaml);
  # `files` maps a path relative to the .textus dir => contents.
  def store_from_manifest(textus_dir, manifest:, zones: [], schemas: {}, files: {})
    zones.each { |z| FileUtils.mkdir_p(File.join(textus_dir, "zones", z)) }
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
    "canon" => "knowledge", "workspace" => "notebook", "quarantine" => "feeds",
    "queue" => "proposals", "derived" => "artifacts"
  }.freeze

  # Preset: a single canon zone "knowledge" holding one leaf entry. The most
  # common read/write shape. Override `kind_zone:` for quarantine/queue/derived;
  # the zone name follows the kind via LANE_ZONE.
  #
  #   let(:store) { minimal_store(root) }                       # knowledge.foo leaf
  #   let(:store) { minimal_store(root, key: "knowledge.doc",   # custom key/path
  #                                     path: "knowledge/doc.md") }
  def minimal_store(root, kind_zone: "canon", zone: LANE_ZONE.fetch(kind_zone), key: "#{zone}.foo", path: "#{zone}/foo.md")
    store_from_manifest(root, zones: [zone], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: #{zone}, kind: #{kind_zone} }
      entries:
        - { key: #{key}, path: #{path}, zone: #{zone}, kind: leaf }
    YAML
  end

  # Preset: a quarantine "feeds" zone + a canon "knowledge" zone, each with one
  # leaf. The standard write-path shape (untrusted intake in quarantine, owned
  # content in canon). Used by put/delete/mv/accept/reject specs.
  def quarantine_store(root)
    store_from_manifest(root, zones: %w[feeds knowledge], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: feeds, kind: quarantine }
        - { name: knowledge, kind: canon }
      entries:
        - { key: feeds.foo, path: feeds/foo.md, zone: feeds, kind: leaf }
        - { key: knowledge.bar, path: knowledge/bar.md, zone: knowledge, kind: leaf }
    YAML
  end

  # Preset: a quarantine "feeds" zone with one intake entry (key feeds.doc) wired
  # to a `test_intake` handler, plus a lifecycle rule. Pass the handler's hook
  # body and the rule's ttl / on_expire (refresh|warn for intake; ADR 0079).
  # Writes the hook into the store's hooks/ dir. Defaults to quarantine; pass
  # `kind_zone: "canon"` for owned-intake — the zone name (and key prefix)
  # follow the kind via LANE_ZONE.
  def intake_store(root, intake_body:, ttl: "1h", on_expire: "refresh", kind_zone: "quarantine")
    zone = LANE_ZONE.fetch(kind_zone)
    store_from_manifest(
      root,
      zones: [zone],
      files: { "hooks/test_intake.rb" => intake_body },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: #{zone}, kind: #{kind_zone} }
        entries:
          - key: #{zone}.doc
            kind: intake
            path: #{zone}/doc.md
            zone: #{zone}
            intake: { handler: test_intake }
        rules:
          - match: #{zone}.doc
            lifecycle: { ttl: #{ttl}, on_expire: #{on_expire} }
      YAML
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
    Textus::Envelope::IO::Reader.new(
      file_store: store.file_store,
      manifest: store.manifest,
    )
  end

  def build_envelope_writer(store, call, reader: nil)
    Textus::Envelope::IO::Writer.new(
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
  # `store.as` reuses the Store's container, whose EventBus is the *same*
  # object as `store.events` — so in-place `store.events.register(...)` probes
  # are visible through it.
  #
  # `build_worker` (below) drives an internal use-case class the façade does
  # not expose (Write::FetchWorker). Pass `events:` to swap the bus wholesale
  # (e.g. a recording probe) via the immutable Container's #with.
  def build_worker(store, ctx, events: nil)
    container = store.container
    container = container.with(events: events) if events
    Textus::Write::FetchWorker.new(container: container, call: ctx)
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
