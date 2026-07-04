RSpec.shared_context "textus_store_fixture" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  after { FileUtils.remove_entry(tmp) }
end

module TextusSpecHelpers
  # Layout-aware paths for specs that assert on runtime artifacts. ADR 0038.
  def audit_log_path(root) = Textus::Protocol::Layout.new(root).audit_log_path
  def audit_dir_path(root) = Textus::Protocol::Layout.new(root).audit_dir_path

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
  #         - key: knowledge.foo
  #   YAML
  #
  # `lanes:` creates the data/<lane> directories; `schemas` maps name => YAML
  # body (written to schemas/<name>.yaml); `files` maps a path relative to the
  # .textus dir => contents.
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
    Textus::Protocol::Session.new(textus_dir)
  end

  def minimal_store(root, lane: "knowledge", key: "#{lane}.foo")
    store_from_manifest(root, lanes: [lane], manifest: <<~YAML)
      version: textus/4
      data:
        #{lane}:
          - key: #{key}
    YAML
  end

  def machine_store(root)
    store_from_manifest(root, lanes: %w[artifacts knowledge], manifest: <<~YAML)
      version: textus/4
      data:
        artifacts:
          - key: artifacts.foo
        knowledge:
          - key: knowledge.bar
    YAML
  end

  def workflow_store(root, workflow_body:, retention: nil, lane: "artifacts")
    manifest = <<~YAML
      version: textus/4
      data:
        #{lane}:
          - key: #{lane}.doc
    YAML
    manifest << "rules:\n  - { match: #{lane}.doc, retention: #{retention} }\n" if retention
    store_from_manifest(
      root,
      lanes: [lane],
      files: {
        "workflows/test_produce.rb" => <<~RUBY,
          Textus.workflow "test_produce" do
            match "#{lane}.doc"
            step :fetch do |_data, _ctx|
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
    Textus::Protocol::EntryStore.new(
      file_system: store.file_system,
      manifest: store.manifest,
      audit_log: store.audit_log,
      layout: store.layout,
      entry_index: store.container.entry_index,
    )
  end

  def build_envelope_writer(store, call, reader: nil)
    _reader = reader || build_envelope_reader(store)
    _call = call
    Textus::Protocol::EntryStore.new(
      file_system: store.file_system,
      manifest: store.manifest,
      audit_log: store.audit_log,
      layout: store.layout,
      entry_index: store.container.entry_index,
    )
  end

  # The Store builds its Container once at construction; this returns it.
  def fresh_container(store)
    store.container
  end

  def converge_now(store, prefix: nil, lane: nil, role: Textus::Value::Role::AUTOMATION)
    with_missing_workflows(store)
    registry = Textus::Workflow::Registry.new(store.container.workflows)
    event_store = store.container.store.event_store

    store.container.manifest.data.entries.each do |entry|
      next if prefix && !entry.key.start_with?(prefix)
      next if lane && entry.lane != lane

      store.container.workflows.each do |wf|
        next unless wf.match?(entry.key) || wf.handled_events.any?

        event_store.emit(
          event_type: "convergence",
          workflow_type: wf.type,
          key: entry.key,
          lane: entry.lane,
          payload: {},
          max_attempts: wf.max_attempts || 3,
        )
      end
    end

    consumer = Textus::Protocol::Events::Consumer.new
    consumer.drain(
      event_store: event_store,
      registry: registry,
      container: store.container,
      call: Textus::Value::Call.build(role: role, correlation_id: SecureRandom.uuid),
    )
  end

  def with_missing_workflows(store)
    registry = Textus::Workflow::Registry.new(store.container.workflows)

    store.container.manifest.data.entries.each do |entry|
      has_publish = entry.publish_to.any? || entry.publish_tree
      already_has = !registry.match_for_key(entry.key).nil?
      next unless has_publish && !already_has

      defn = Textus::Workflow::DSL::Definition.new("auto-#{entry.key}")
      defn.handles "entry.written"
      defn.match(entry.key)
      defn.step :passthrough do |data, _ctx|
        data || { content: nil }
      end
      defn.publish
      store.container.workflows << defn
    end
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
