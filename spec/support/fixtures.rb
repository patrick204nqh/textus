RSpec.shared_context "textus_store_fixture" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  after { FileUtils.remove_entry(tmp) }
end

module TextusSpecHelpers
  # Builds a slim Application::Context for tests. Callers pass the role
  # (and optionally correlation_id, dry_run) — collaborators come from the
  # store, not from Context.
  def test_ctx(role: "human", correlation_id: nil, dry_run: false)
    Textus::Application::Context.build(
      role: role, correlation_id: correlation_id, dry_run: dry_run,
    )
  end

  def build_envelope_io(store, ctx)
    Textus::Application::Writes::EnvelopeIO.new(
      file_store: store.file_store,
      manifest: store.manifest,
      schemas: store.schemas,
      audit_log: store.audit_log,
      ctx: ctx,
    )
  end

  # Builds the explicit-port kwargs that every Writes use case takes from
  # an explicit store + slim Context pair.
  def writes_ports(store, ctx, envelope_io: nil)
    ops = Textus::Operations.new(
      ctx: ctx,
      manifest: store.manifest,
      file_store: store.file_store,
      schemas: store.schemas,
      audit_log: store.audit_log,
      bus: store.bus,
      root: store.root,
      store: store,
    )
    {
      ctx: ctx,
      manifest: store.manifest,
      file_store: store.file_store,
      schemas: store.schemas,
      audit_log: store.audit_log,
      envelope_io: envelope_io || build_envelope_io(store, ctx),
      bus: store.bus,
      authorizer: Textus::Domain::Authorizer.new(manifest: store.manifest),
      root: store.root,
      store: store,
      hook_context: ops.hook_context,
    }
  end

  def build_put(store, ctx, envelope_io: nil)
    p = writes_ports(store, ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Put.new(
      ctx: p[:ctx], manifest: p[:manifest], envelope_io: p[:envelope_io],
      bus: p[:bus], authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_delete(store, ctx, envelope_io: nil)
    p = writes_ports(store, ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Delete.new(
      ctx: p[:ctx], manifest: p[:manifest], envelope_io: p[:envelope_io],
      bus: p[:bus], authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_mv(store, ctx, envelope_io: nil)
    p = writes_ports(store, ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Mv.new(
      ctx: p[:ctx], manifest: p[:manifest],
      envelope_io: p[:envelope_io],
      bus: p[:bus], authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_accept(store, ctx, envelope_io: nil)
    p = writes_ports(store, ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Accept.new(
      ctx: p[:ctx], manifest: p[:manifest], file_store: p[:file_store],
      schemas: p[:schemas],
      envelope_io: p[:envelope_io], bus: p[:bus],
      authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_reject(store, ctx, envelope_io: nil)
    p = writes_ports(store, ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Reject.new(
      ctx: p[:ctx], manifest: p[:manifest], file_store: p[:file_store],
      envelope_io: p[:envelope_io], bus: p[:bus],
      authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_worker(store, ctx)
    ops = Textus::Operations.new(
      ctx: ctx,
      manifest: store.manifest,
      file_store: store.file_store,
      schemas: store.schemas,
      audit_log: store.audit_log,
      bus: store.bus,
      root: store.root,
      store: store,
    )
    Textus::Application::Refresh::Worker.new(
      ctx: ctx, manifest: store.manifest, envelope_io: build_envelope_io(store, ctx),
      bus: store.bus,
      store: store, authorizer: Textus::Domain::Authorizer.new(manifest: store.manifest),
      hook_context: ops.hook_context
    )
  end

  def build_publish(store, ctx)
    p = writes_ports(store, ctx)
    Textus::Application::Writes::Publish.new(
      ctx: p[:ctx], manifest: p[:manifest], file_store: p[:file_store],
      bus: p[:bus], root: p[:root], store: p[:store], hook_context: p[:hook_context]
    )
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
