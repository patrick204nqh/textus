RSpec.shared_context "textus_store_fixture" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  after { FileUtils.remove_entry(tmp) }
end

module TextusSpecHelpers
  # Builds a Textus::Call value for tests. Callers pass the role (and
  # optionally correlation_id, dry_run) — collaborators come from the
  # Store/Container, not from Call.
  def test_ctx(role: "human", correlation_id: nil, dry_run: false)
    Textus::Call.build(
      role: role, correlation_id: correlation_id, dry_run: dry_run,
    )
  end

  def build_envelope_reader(store)
    Textus::Application::Envelope::Reader.new(
      file_store: store.file_store,
      manifest: store.manifest,
    )
  end

  def build_envelope_writer(store, ctx, reader: nil)
    Textus::Application::Envelope::Writer.new(
      file_store: store.file_store,
      manifest: store.manifest,
      schemas: store.schemas,
      audit_log: store.audit_log,
      ctx: ctx,
      reader: reader || build_envelope_reader(store),
    )
  end

  # Builds a fresh Container from the Store. Tests sometimes mutate
  # @events/@rpc on the Store after construction (e.g. to install a probe
  # event bus); using fresh containers ensures we see those mutations.
  def fresh_container(store)
    Textus::Container.from_store(store)
  end

  # Returns a RoleScope-derived Hooks::Context suitable for use cases that
  # take hook_context:. Mirrors the wiring RoleScope does at runtime.
  def build_hook_context(store, ctx, container: nil)
    container ||= fresh_container(store)
    scope = Textus::RoleScope.new(
      container: container, role: ctx.role,
      dry_run: ctx.dry_run, correlation_id: ctx.correlation_id
    )
    Textus::Hooks::Context.new(scope: scope)
  end

  def build_put(store, ctx)
    container = fresh_container(store)
    Textus::Application::Write::Put.new(
      container: container, call: ctx, hook_context: build_hook_context(store, ctx, container: container),
    )
  end

  def build_delete(store, ctx)
    container = fresh_container(store)
    Textus::Application::Write::Delete.new(
      container: container, call: ctx, hook_context: build_hook_context(store, ctx, container: container),
    )
  end

  def build_mv(store, ctx)
    container = fresh_container(store)
    Textus::Application::Write::Mv.new(
      container: container, call: ctx, hook_context: build_hook_context(store, ctx, container: container),
    )
  end

  def build_accept(store, ctx)
    container = fresh_container(store)
    Textus::Application::Write::Accept.new(
      container: container, call: ctx, hook_context: build_hook_context(store, ctx, container: container),
    )
  end

  def build_reject(store, ctx)
    container = fresh_container(store)
    Textus::Application::Write::Reject.new(
      container: container, call: ctx, hook_context: build_hook_context(store, ctx, container: container),
    )
  end

  def build_worker(store, ctx)
    container = fresh_container(store)
    Textus::Application::Write::RefreshWorker.new(
      container: container, call: ctx, hook_context: build_hook_context(store, ctx, container: container),
    )
  end

  def build_publish(store, ctx)
    Textus::Application::Write::Publish.new(container: fresh_container(store), call: ctx)
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
