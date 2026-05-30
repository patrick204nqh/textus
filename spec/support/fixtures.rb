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

  def build_put(store, ctx)
    Textus::Write::Put.new(container: fresh_container(store), call: ctx)
  end

  def build_delete(store, ctx)
    Textus::Write::Delete.new(container: fresh_container(store), call: ctx)
  end

  def build_mv(store, ctx)
    Textus::Write::Mv.new(container: fresh_container(store), call: ctx)
  end

  def build_accept(store, ctx)
    Textus::Write::Accept.new(container: fresh_container(store), call: ctx)
  end

  def build_reject(store, ctx)
    Textus::Write::Reject.new(container: fresh_container(store), call: ctx)
  end

  def build_worker(store, ctx)
    Textus::Write::FetchWorker.new(container: fresh_container(store), call: ctx)
  end

  def build_publish(store, ctx)
    Textus::Write::Publish.new(container: fresh_container(store), call: ctx)
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
