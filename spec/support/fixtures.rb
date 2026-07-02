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
  #     data:
  #       knowledge:
  #         - { key: knowledge.foo, path: knowledge/foo.md }
  #   YAML
  #
  # `lanes:` creates the data/<lane> directories; `schemas` maps name => YAML
  # body (written to schemas/<name>.yaml); `files` maps a path relative to the
  # .textus dir => contents.
  def store_from_manifest(textus_dir, manifest:, lanes: [], schemas: {}, files: {})
    manifest = migrate_legacy_manifest(manifest)
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

  # Preset: a single lane (default knowledge) holding one leaf entry.
  #
  #   let(:store) { minimal_store(root) }                          # knowledge.foo leaf
  #   let(:store) { minimal_store(root, lane: "knowledge",          # custom lane/key/path
  #                               key: "knowledge.doc",
  #                               path: "knowledge/doc.md") }
  def minimal_store(root, lane: "knowledge", key: "#{lane}.foo", path: "#{lane}/foo.md")
    store_from_manifest(root, lanes: [lane], manifest: <<~YAML)
      version: textus/4
      data:
        #{lane}:
          - { key: #{key}, path: #{path} }
    YAML
  end

  # Preset: two lanes, each with one leaf. One automation-only (artifacts),
  # one writable by human/agent (knowledge). For write-gating specs.
  def machine_store(root)
    store_from_manifest(root, lanes: %w[artifacts knowledge], manifest: <<~YAML)
      version: textus/4
      data:
        artifacts:
          - { key: artifacts.foo, path: artifacts/foo.md }
        knowledge:
          - { key: knowledge.bar, path: knowledge/bar.md }
    YAML
  end

  # Preset: an artifacts lane with one produced entry driven by a
  # user-registered workflow. Pass the workflow step body as a block.
  # Optionally pass `retention:` to add a retention rule.
  def workflow_store(root, workflow_body:, retention: nil, lane: "artifacts")
    manifest = <<~YAML
      version: textus/4
      data:
        #{lane}:
          - key: #{lane}.doc
            path: #{lane}/doc.md
    YAML
    manifest << "rules:\n  - { match: #{lane}.doc, retention: #{retention} }\n" if retention
    store_from_manifest(
      root,
      lanes: [lane],
      files: {
        "workflows/test_produce.rb" => <<~RUBY,
          Textus.workflow "test_produce" do
            match "#{lane}.doc"
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
    with_missing_workflows(store)
    Textus::Store::Jobs::Planner.seed(container: store.container, queue: queue, role: role)
    Textus::Store::Jobs::Worker.for(container: store.container, queue: queue).drain
  end

  # Detect old-format manifests (roles:/lanes:/entries: at top level) and
  # auto-convert to the data:-grouped format. Keeps legacy conformance specs
  # running without manual migration.
  def migrate_legacy_manifest(yaml_str)
    raw = YAML.safe_load(yaml_str, aliases: false)
    return yaml_str if raw["data"]  # already new format

    entries = Array(raw["entries"]).map { |e|
      e.reject { |k, _| %w[owner kind nested].include?(k) }
    }
    return yaml_str if entries.empty?  # nothing to convert (e.g. version-only test)

    grouped = entries.group_by { |e| e.delete("lane") }
    raw["data"] = grouped
    raw.delete("roles")
    raw.delete("lanes")
    YAML.dump(raw).sub(/\A---\n/, "")
  end

  # Auto-register no-op workflows for manifest entries that have publish config
  # but no matching workflow definition. This lets legacy test manifests work
  # with the workflow-only Planner.
  def with_missing_workflows(store)
    store.container.manifest.data.entries.each do |entry|
      has_publish = entry.publish_to.any? || entry.publish_tree
      already_has = store.container.workflows.any? { |d| d.match?(entry.key) }
      next unless has_publish && !already_has

      defn = Textus::Workflow::DSL::Definition.new("auto-#{entry.key}")
      defn.match(entry.key)
      defn.step(:passthrough) { |data, _ctx| data || { content: nil } }
      store.container.workflows << defn
    end
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
