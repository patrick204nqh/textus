RSpec.shared_context "textus_store_fixture" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  after { FileUtils.remove_entry(tmp) }
end

module TextusSpecHelpers
  # Layout-aware paths for specs that assert on runtime artifacts. ADR 0038.
  def audit_log_path(root) = Textus::Store::Layout.new(root).audit_log_path
  def audit_dir_path(root) = Textus::Store::Layout.new(root).audit_dir_path

  # Writes a manifest (+ optional zone dirs, schema files, and seed files)
  # into `textus_dir` and returns the Store. Pair with the
  # "textus_store_fixture" shared context, which provides `root` (the .textus
  # dir) and tmp cleanup, to drop the per-spec build_store/mktmpdir boilerplate:
  #
  #   include_context "textus_store_fixture"
  #   let(:store) { store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML) }
  #     version: textus/4
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
      version: textus/4
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
      version: textus/4
      lanes:
        - { name: feeds, kind: machine }
        - { name: knowledge, kind: canon }
      entries:
        - { key: feeds.foo, path: feeds/foo.md, lane: feeds, kind: leaf }
        - { key: knowledge.bar, path: knowledge/bar.md, lane: knowledge, kind: leaf }
    YAML
  end

  # Preset: a machine lane with one produced entry (key artifacts.doc) driven
  # by a user-registered workflow. Pass the workflow step body as a block.
  # Optionally pass `retention:` to add a retention rule.
  def workflow_store(root, workflow_body:, retention: nil, lane_kind: "machine")
    zone = LANE_ZONE.fetch(lane_kind)
    manifest = <<~YAML
      version: textus/4
      lanes:
        - { name: #{zone}, kind: #{lane_kind} }
      entries:
        - key: #{zone}.doc
          path: #{zone}/doc.md
          lane: #{zone}
    YAML
    manifest << "rules:\n  - { match: #{zone}.doc, retention: #{retention} }\n" if retention
    store_from_manifest(
      root,
      lanes: [zone],
      files: {
        "workflows/test_produce.rb" => <<~RUBY,
          Textus.workflow "test_produce" do
            match "#{zone}.doc"
            step :fetch do |data, ctx|
              #{workflow_body}
            end
            publish
          end
        RUBY
      },
      manifest: manifest,
    )
  end

  # Builds a Textus::Value::Call value for tests. Callers pass the role (and
  # optionally correlation_id, dry_run) — collaborators come from the
  # Store/Container, not from Call.
  def test_ctx(role: "human", correlation_id: nil, dry_run: false)
    Textus::Value::Call.build(
      role: role, correlation_id: correlation_id, dry_run: dry_run,
    )
  end

  def build_envelope_reader(store)
    Textus::Store::Entry::Reader.new(
      file_store: store.file_store,
      manifest: store.manifest,
      layout: store.layout,
    )
  end

  def build_envelope_writer(store, call, reader: nil)
    reader ||= build_envelope_reader(store)
    Textus::Store::Entry::Writer.new(
      file_store: store.file_store,
      manifest: store.manifest,
      schemas: store.schemas,
      audit_log: store.audit_log,
      call: call,
      reader: reader,
      layout: store.layout,
    )
  end

  # The Store builds its Container once at construction; this returns it.
  def fresh_container(store)
    store.container
  end

  # Seed convergence jobs for the given scope and then burn the queue through
  # Maintenance::Drain (which is queue-burn only).
  def converge_now(store, prefix: nil, lane: nil, role: Textus::Value::Role::AUTOMATION) # rubocop:disable Lint/UnusedMethodArgument
    queue = Textus::Store::Jobs::Queue.new(store: store.job_store)
    queue.purge("done")
    Textus::Store::Jobs::Planner.seed(container: store.container, queue: queue, role: role)
    Textus::Store::Jobs::Worker.for(container: store.container, queue: queue).drain
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
