RSpec.shared_context "textus_store_fixture" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  after { FileUtils.remove_entry(tmp) }
end

module TextusSpecHelpers
  # Writes a manifest (+ optional zone dirs, schema files, and seed files)
  # into `textus_dir` and returns the Store. Pair with the
  # "textus_store_fixture" shared context, which provides `root` (the .textus
  # dir) and tmp cleanup, to drop the per-spec build_store/mktmpdir boilerplate:
  #
  #   include_context "textus_store_fixture"
  #   let(:store) { store_from_manifest(root, zones: %w[working], manifest: <<~YAML) }
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

  # Preset: a single canon zone "working" holding one leaf entry. The most
  # common read/write shape. Override `kind_zone:` for quarantine/queue/derived.
  #
  #   let(:store) { minimal_store(root) }                     # working.foo leaf
  #   let(:store) { minimal_store(root, key: "working.doc",   # custom key/path
  #                                     path: "working/doc.md") }
  def minimal_store(root, key: "working.foo", path: "working/foo.md", zone: "working", kind_zone: "canon")
    store_from_manifest(root, zones: [zone], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: #{zone}, kind: #{kind_zone} }
      entries:
        - { key: #{key}, path: #{path}, zone: #{zone}, kind: leaf }
    YAML
  end

  # Preset: a quarantine "working" zone + a canon "identity" zone, each with
  # one leaf. The standard write-path shape (untrusted intake in quarantine,
  # owned content in canon). Used by put/delete/mv/accept/reject specs.
  def quarantine_store(root)
    store_from_manifest(root, zones: %w[working identity], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: quarantine }
        - { name: identity, kind: canon }
      entries:
        - { key: working.foo, path: working/foo.md, zone: working, kind: leaf }
        - { key: identity.bar, path: identity/bar.md, zone: identity, kind: leaf }
    YAML
  end

  # Preset: a "working" zone with one intake entry (key working.doc) wired to a
  # `test_intake` handler, plus a fetch rule. Pass the handler's hook body and
  # the rule's ttl / on_stale. Writes the hook into the store's hooks/ dir. The
  # working zone defaults to quarantine; pass `kind_zone: "canon"` for
  # owned-intake. For a different key/path, use store_from_manifest directly.
  def intake_store(root, intake_body:, ttl: "1h", on_stale: "warn", kind_zone: "quarantine")
    store_from_manifest(
      root,
      zones: %w[working],
      files: { "hooks/test_intake.rb" => intake_body },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: working, kind: #{kind_zone} }
        entries:
          - key: working.doc
            kind: intake
            path: working/doc.md
            zone: working
            intake: { handler: test_intake }
        rules:
          - match: working.doc
            fetch: { ttl: #{ttl}, on_stale: #{on_stale} }
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

  # Builds a fresh Container from the Store. Tests sometimes mutate
  # @events/@rpc on the Store after construction (e.g. to install a probe
  # event bus); using fresh containers ensures we see those mutations.
  def fresh_container(store)
    Textus::Container.from_store(store)
  end

  # ── Use-case invocation idiom ───────────────────────────────────────────
  # Prefer the public façade for anything reachable through it:
  #
  #   store.as(role, correlation_id:, dry_run:).put("working.foo", meta:, body:)
  #
  # `store.as` reuses the Store's memoized container, whose EventBus is the
  # *same* object as `store.events` — so in-place `store.events.register(...)`
  # probes are visible through it.
  #
  # `build_worker` (below) builds a FRESH container each call. It exists for
  # specs that swap the bus wholesale (`store.instance_variable_set(:@events,
  # probe)`) or drive an internal use-case class the façade does not expose
  # (Write::FetchWorker). For those the memoized container would be stale, so a
  # fresh one is required.
  def build_worker(store, ctx)
    Textus::Write::FetchWorker.new(container: fresh_container(store), call: ctx)
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
